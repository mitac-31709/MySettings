# Graphical multi-session stack: greeter + Console + Plasma + GNOME + Xfce + Hyprland.
{ ... }:

{
  imports = [
    ./plasma.nix
    ./gnome.nix
    ./xfce.nix
    ./greetd.nix
    ./console-gui.nix
    ./hyprland.nix
  ];

  # Shared by Plasma / GNOME / Xfce / Hyprland sessions (layout + printing).
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "jp";
    variant = "";
  };
  services.printing.enable = true;
}
