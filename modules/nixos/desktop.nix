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

  # Desktop-specific portals. Sway's config (gtk default + wlr ScreenCast/
  # Screenshot) comes from nixpkgs programs.sway — do not redefine
  # xdg.portal.config.sway.default here (conflicts at equal priority).
  # Without a Plasma split, stacks fight under every session (duplicate D-Bus names).
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config = {
      common.default = [ "gtk" ];
      kde = {
        default = [
          "kde"
          "gtk"
        ];
      };
    };
  };
}
