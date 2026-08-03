# GNOME-specific Home Manager settings (shortcuts / input). Appearance stays stock.
{ pkgs, ... }:

let
  ghostty = "${pkgs.ghostty}/bin/ghostty";
in
{
  # Super+R → Overview search (parity with Plasma KRunner / Hyprland launchers).
  # Ctrl+Alt+T → Ghostty; touchpad matches Plasma (natural off / tap on / DWT off).
  # Super alone (mutter overlay-key) still opens Overview; do not restyle Shell.
  dconf.settings = {
    "org/gnome/shell/keybindings" = {
      toggle-overview = [ "<Super>r" ];
    };

    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
      # Super+L is GNOME's default screensaver/lock binding; leave stock.
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "Ghostty";
      command = ghostty;
      binding = "<Primary><Alt>t";
    };

    "org/gnome/desktop/peripherals/touchpad" = {
      natural-scroll = false;
      tap-to-click = true;
      disable-while-typing = false;
    };
  };
}
