# Chromebook power management: zram, auto-cpufreq, power-button chords,
# USB-C sink preference (power banks charge the laptop).
{
  pkgs,
  config,
  ...
}:

let
  # Power button is a separate ACPI input device from the keyboard, so keyd
  # cannot chord power+Back. This watcher implements ChromeOS-like combos.
  chromebook-power-chords = pkgs.writers.writePython3Bin "chromebook-power-chords" {
    libraries = [ pkgs.python3Packages.evdev ];
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ../chromebook-power-chords.py);

  # PR_SWAP via sysfs often returns EIO (partner keeps us as source). Talk to
  # the Cros EC: USB_PD_CTRL_ROLE_FORCE_SINK + charge-port override.
  chromebook-typec-prefer-sink = pkgs.writers.writePython3Bin "chromebook-typec-prefer-sink" {
    flakeIgnore = [
      "E501"
      "W503"
      "E203"
    ];
  } (builtins.readFile ./typec-prefer-sink.py);
in
{
  # ~8 GiB RAM, no disk swap partition, tight root (Chromebook leftover
  # partitions). zram at 100% of RAM ≈ 8 GiB compressed swap (zstd); avoids
  # a swapfile on the ~90G root while giving headroom for Plasma + browsers.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
    algorithm = "zstd";
  };

  # zram-friendly VM knobs: swap earlier into cheap compressed RAM, avoid
  # reading ahead multiple pages from zram (page-cluster=0).
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
    "vm.vfs_cache_pressure" = 50;
  };

  # Sustained performance under Chromebook thermal limits.
  services.thermald.enable = true;

  # auto-cpufreq manages governors/turbo; conflicts with power-profiles-daemon.
  services.power-profiles-daemon.enable = false;
  services.auto-cpufreq = {
    enable = true;
    settings = {
      charger = {
        governor = "performance";
        turbo = "auto";
      };
      battery = {
        governor = "powersave";
        turbo = "auto";
      };
    };
  };

  # Power button is owned by chromebook-power-chords.service (grab + chords).
  # Keep logind from also suspending/powering-off on KEY_POWER.
  services.logind.settings.Login = {
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "ignore";
  };

  systemd.services.chromebook-power-chords = {
    description = "Chromebook power-button chords (logout / reboot / suspend)";
    documentation = [ "file://${../chromebook-power-chords.py}" ];
    wantedBy = [ "multi-user.target" ];
    after = [
      "keyd.service"
      "systemd-logind.service"
    ];
    wants = [ "keyd.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${chromebook-power-chords}/bin/chromebook-power-chords";
      Restart = "on-failure";
      RestartSec = "1s";
      # Root: grab LNXPWRBN, call loginctl/systemctl.
      Environment = [ "POWER_CHORDS_USER=${config.users.users.mitac.name}" ];
    };
  };

  environment.systemPackages = [ chromebook-typec-prefer-sink ];

  systemd.services.chromebook-typec-prefer-sink = {
    description = "Prefer USB-C sink role (charge from power banks)";
    documentation = [ "file://${./typec-prefer-sink.py}" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${chromebook-typec-prefer-sink}/bin/chromebook-typec-prefer-sink";
    };
  };

  # Idle preference: FORCE_SINK on all ports so the next attach tries as sink
  # (avoids Try.SRC winning against power banks before userspace can react).
  systemd.services.chromebook-typec-force-sink-boot = {
    description = "Force Cros EC USB-C ports to sink at boot";
    documentation = [ "file://${./typec-prefer-sink.py}" ];
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${chromebook-typec-prefer-sink}/bin/chromebook-typec-prefer-sink --force-all-sink --retries 1 --settle 0.2";
    };
  };

  # Partner add / port change → FORCE_SINK + charge override (non-blocking).
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="typec", KERNEL=="port[0-9]*-partner", \
      RUN+="${pkgs.systemd}/bin/systemctl --no-block start chromebook-typec-prefer-sink.service"
    ACTION=="change", SUBSYSTEM=="typec", KERNEL=="port[0-9]*", \
      RUN+="${pkgs.systemd}/bin/systemctl --no-block start chromebook-typec-prefer-sink.service"
  '';
}
