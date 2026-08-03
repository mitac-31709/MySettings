# Graphical multi-session stack: greeter + Plasma + GNOME + Xfce + Sway + Hyprland.
{ ... }:

{
  imports = [
    ./plasma.nix
    ./gnome.nix
    ./xfce.nix
    ./sway.nix
    ./greetd.nix
    ./console-gui.nix
    ./hyprland.nix
  ];

  # Shared by Plasma / GNOME / Xfce / Sway / Hyprland sessions (layout + printing).
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "jp";
    variant = "";
  };
  services.printing.enable = true;
}
