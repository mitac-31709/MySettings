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

  # cros_ec_typec has no try_role; preferred_role stays source. Swap to sink
  # after dual-role partners connect so power banks charge the Chromebook.
  chromebook-typec-prefer-sink = pkgs.writeShellApplication {
    name = "chromebook-typec-prefer-sink";
    text = builtins.readFile ./typec-prefer-sink.sh;
  };
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

  systemd.services.chromebook-typec-prefer-sink = {
    description = "Prefer USB-C sink role (charge from power banks)";
    documentation = [ "file://${./typec-prefer-sink.sh}" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${chromebook-typec-prefer-sink}/bin/chromebook-typec-prefer-sink";
    };
  };

  # Partner add + power_role change → oneshot PR_SWAP to sink (non-blocking).
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="typec", KERNEL=="port[0-9]*-partner", \
      RUN+="${pkgs.systemd}/bin/systemctl --no-block start chromebook-typec-prefer-sink.service"
    ACTION=="change", SUBSYSTEM=="typec", KERNEL=="port[0-9]*", ATTR{power_role}=="source [sink]", \
      RUN+="${pkgs.systemd}/bin/systemctl --no-block start chromebook-typec-prefer-sink.service"
  '';
}
