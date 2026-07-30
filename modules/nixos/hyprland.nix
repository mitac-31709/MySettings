{ pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    withUWSM = false;
    xwayland.enable = true;
  };

  # Desktop-specific portals: Plasma uses KDE; Hyprland uses xdph + gtk.
  # Without this, both stacks fight under every session (duplicate D-Bus names,
  # "Could not register app ID" spam).
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-hyprland
    ];
    config = {
      common.default = [ "gtk" ];
      hyprland = {
        default = [
          "hyprland"
          "gtk"
        ];
      };
      kde = {
        default = [
          "kde"
          "gtk"
        ];
      };
    };
  };

  environment.systemPackages = with pkgs; [
    quickshell
    wl-clipboard
    hyprpicker
  ];
}
