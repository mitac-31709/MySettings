# GNOME-specific Home Manager settings (shortcuts). Appearance stays stock.
{ ... }:

{
  # Super+R → Overview search field (parity with Plasma KRunner / Hyprland launchers).
  # Super alone (mutter overlay-key) still opens Overview; do not restyle Shell.
  dconf.settings = {
    "org/gnome/shell/keybindings" = {
      toggle-overview = [ "<Super>r" ];
    };
  };
}
