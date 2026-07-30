{ pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    withUWSM = false;
    xwayland.enable = true;
  };

  # Shared Wayland portal stack for Hyprland sessions (Plasma keeps its own).
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-hyprland
    ];
  };

  environment.systemPackages = with pkgs; [
    quickshell
    wl-clipboard
    hyprpicker
  ];
}
