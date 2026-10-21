# Graphical desktop stack: greeter + Sway + console-gui + portals.
{
  pkgs,
  ...
}:

{
  imports = [
    ./sway.nix
    ./greetd.nix
    ./console-gui.nix
  ];

  # Layout + printing (used by the Sway session).
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "jp";
    variant = "";
  };
  services.printing.enable = true;

  # Desktop portals. Sway's config (gtk default + wlr ScreenCast/Screenshot)
  # comes from nixpkgs programs.sway — do not redefine
  # xdg.portal.config.sway.default here (conflicts at equal priority).
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config = {
      common.default = [ "gtk" ];
    };
  };
}
