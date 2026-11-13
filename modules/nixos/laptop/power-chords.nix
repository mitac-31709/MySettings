# Shared power-button chords across separate input devices (Power Button + keyd).
{
  pkgs,
  config,
  ...
}:

let
  # Power button is a separate ACPI input device from the keyboard, so keyd
  # cannot chord power+F1/Back. This watcher implements short/long/chord combos.
  power-chords = pkgs.writers.writePython3Bin "power-chords" {
    libraries = [ pkgs.python3Packages.evdev ];
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ./power-chords.py);
in
{
  # Power button is owned by power-chords.service (grab + chords).
  # Keep logind from also suspending/powering-off on KEY_POWER.
  services.logind.settings.Login = {
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "ignore";
  };

  systemd.services.power-chords = {
    description = "Power-button chords (logout / reboot / suspend / poweroff)";
    documentation = [ "file://${./power-chords.py}" ];
    wantedBy = [ "multi-user.target" ];
    after = [
      "keyd.service"
      "systemd-logind.service"
    ];
    wants = [ "keyd.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${power-chords}/bin/power-chords";
      Restart = "on-failure";
      RestartSec = "1s";
      # Root: grab Power Button nodes, call loginctl/systemctl.
      Environment = [ "POWER_CHORDS_USER=${config.users.users.mitac.name}" ];
    };
  };
}
