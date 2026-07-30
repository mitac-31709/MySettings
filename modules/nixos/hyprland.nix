{ pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    withUWSM = false;
    xwayland.enable = true;
  };

  # Desktop-specific portals: Plasma=KDE, GNOME=gnome, Hyprland=xdph+gtk.
  # Without this, stacks fight under every session (duplicate D-Bus names,
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
      gnome = {
        default = [
          "gnome"
          "gtk"
        ];
      };
    };
  };

  # Runtime deps for Illogical Impulse / end4-pC hyprland.start autostart.
  environment.systemPackages = with pkgs; [
    quickshell
    wl-clipboard
    hyprpicker
    cliphist
    hypridle
    hyprsunset
    brightnessctl
    bibata-cursors
    python3
  ];
}
