# Graphical multi-session stack: greeter + Plasma + Sway + Hyprland.
{ pkgs, ... }:

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

  # Thunar (Sway primary GUI filer). xfconf keeps preferences across sessions.
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-archive-plugin
      thunar-volman
    ];
  };
  programs.xfconf.enable = true;
  services.gvfs.enable = true; # trash / MTP / network mounts
  services.tumbler.enable = true; # image thumbnails
}
