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

  # Shared by Plasma / GNOME / Hyprland sessions (layout + printing).
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "jp";
    variant = "";
  };
  services.printing.enable = true;
}
