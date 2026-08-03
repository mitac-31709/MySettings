# Home Manager entry for mitac: identity + session/program imports.
{ ... }:

{
  imports = [
    ./shell.nix
    ./programs.nix
    ./plasma.nix
    ./gnome.nix
    ./xfce.nix
    ./sessions/hyprland.nix
  ];

  home.username = "mitac";
  home.homeDirectory = "/home/mitac";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
}
