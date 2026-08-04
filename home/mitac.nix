# Home Manager entry for mitac: identity + session/program imports.
{ ... }:

{
  imports = [
    ./shell.nix
    ./programs.nix
    ./clipboard.nix
    ./plasma.nix
    ./gnome.nix
    ./xfce.nix
    ./sway.nix
    ./sessions/hyprland.nix
  ];

  home.username = "mitac";
  home.homeDirectory = "/home/mitac";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
}
