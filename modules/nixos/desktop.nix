# Graphical multi-session stack: greeter + Sway (primary) + Plasma.
{
  pkgs,
  ...
}:

{
  imports = [
    ./plasma.nix
    ./sway.nix
    ./greetd.nix
    ./console-gui.nix
  ];

  # Shared by Sway / Plasma (layout + printing).
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "jp";
    variant = "";
  };
  services.printing.enable = true;

  # Desktop-specific portals: Plasma=KDE, Sway=wlr (from programs.sway) + gtk.
  # Without a split config, stacks fight under every session (duplicate D-Bus names).
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config = {
      common.default = [ "gtk" ];
      sway = {
        default = [
          "wlr"
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
}
