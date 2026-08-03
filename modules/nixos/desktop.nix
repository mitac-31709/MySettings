# Graphical multi-session stack: greeter + Console + Plasma + GNOME + Hyprland.
{ ... }:

{
  imports = [
    ./plasma.nix
    ./gnome.nix
    ./greetd.nix
    ./console-gui.nix
    ./hyprland.nix
  ];
}
