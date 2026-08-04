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
    "org/gnome/shell" = {
      enabled-extensions = [ "GPaste@gnome-shell-extensions.gnome.org" ];
    };

    "org/gnome/shell/keybindings" = {
      toggle-overview = [ "<Super>r" ];
    };

    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
      ];
      # Super+L is GNOME's default screensaver/lock binding; leave stock.
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "Ghostty";
      command = ghostty;
      binding = "<Primary><Alt>t";
    };

    # GPaste UI (programs.gpaste.enable); Super+V matches Plasma / Sway.
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1" = {
      name = "Clipboard history";
      command = "gpaste-client ui";
      binding = "<Super>v";
    };

    "org/gnome/desktop/peripherals/touchpad" = {
      natural-scroll = false;
      tap-to-click = true;
      disable-while-typing = false;
    };
  };
}
