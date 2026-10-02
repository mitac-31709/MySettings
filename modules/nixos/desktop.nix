# Graphical multi-session stack: greeter + Plasma + Sway + Hyprland.
{ ... }:

{
  imports = [
    ./plasma.nix
    ./sway.nix
    ./greetd.nix
    ./console-gui.nix
    ./hyprland.nix
  ];

  # Shared by Plasma / Sway / Hyprland sessions (layout + printing).
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "jp";
    variant = "";
  };
  services.printing.enable = true;
}
