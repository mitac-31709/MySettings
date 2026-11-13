# Chromebook-only USB-C sink preference via Cros EC (power banks charge the laptop).
# Shared zram, thermald, auto-cpufreq, and power-chords live in ../laptop/power.nix.
{
  pkgs,
  ...
}:

let
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
  environment.systemPackages = [ chromebook-typec-prefer-sink ];

  systemd.services.chromebook-typec-prefer-sink = {
    description = "USB-C power-role policy (sink chargers; source phones/AC)";
    documentation = [ "file://${./typec-prefer-sink.py}" ];
    # pd_control used to re-enter via typec CHANGE udev in a tight loop.
    unitConfig = {
      ConditionPathExists = "/dev/cros_ec";
      StartLimitIntervalSec = "30";
      StartLimitBurst = "5";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${chromebook-typec-prefer-sink}/bin/chromebook-typec-prefer-sink";
    };
  };

  # Boot: on battery → idle FORCE_SINK (wall chargers); on AC → other ports source.
  systemd.services.chromebook-typec-power-policy-boot = {
    description = "Apply Cros EC USB-C power-role policy at boot";
    documentation = [ "file://${./typec-prefer-sink.py}" ];
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/dev/cros_ec";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${chromebook-typec-prefer-sink}/bin/chromebook-typec-prefer-sink --boot";
    };
  };

  # Partner plug + charger online only (not every typec CHANGE — that loops).
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="typec", KERNEL=="port[0-9]*-partner", TEST=="/dev/cros_ec", \
      RUN+="${pkgs.systemd}/bin/systemctl --no-block start chromebook-typec-prefer-sink.service"
    ACTION=="change", SUBSYSTEM=="power_supply", ENV{POWER_SUPPLY_NAME}=="AC|CROS_USBPD_CHARGER*", ENV{POWER_SUPPLY_ONLINE}=="1", TEST=="/dev/cros_ec", \
      RUN+="${pkgs.systemd}/bin/systemctl --no-block start chromebook-typec-prefer-sink.service"
  '';
}
