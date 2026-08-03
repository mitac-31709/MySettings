# Xfce-specific Home Manager settings (shortcuts). Appearance stays stock.
{ pkgs, ... }:

let
  ghostty = "${pkgs.ghostty}/bin/ghostty";
  appfinder = "${pkgs.xfce4-appfinder}/bin/xfce4-appfinder";
  xflock4 = "${pkgs.xfce4-session}/bin/xflock4";
in
{
  # Super+R → App Finder; Ctrl+Alt+T → Ghostty; Super+L → lock.
  # Do not restyle panel/theme/wallpaper.
  xfconf.settings = {
    xfce4-keyboard-shortcuts = {
      "commands/custom/<Super>r" = appfinder;
      "commands/custom/<Primary><Alt>t" = ghostty;
      "commands/custom/<Super>l" = xflock4;
    };
  };
}
