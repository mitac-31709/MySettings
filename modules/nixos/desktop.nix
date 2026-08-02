# Graphical multi-session stack: greeter + Console + Plasma + Hyprland shells.
{ ... }:

{
  imports = [
    ./plasma.nix
    ./greetd.nix
    ./console-gui.nix
    ./hyprland.nix
  ];
}
