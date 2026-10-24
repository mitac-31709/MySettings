# Home Manager entry for mitac: identity + session/program imports.
{ ... }:

{
  imports = [
    ./shell.nix
    ./programs.nix
    ./clipboard.nix
    ./lan-mouse.nix
    ./taildrop.nix
    ./uniclipboard.nix
    ./chatgpt-cua-indicator.nix
    ./ai-status-chips.nix
    ./vivaldi-chatgpt-extension.nix
    ./jquake.nix
    ./sway.nix
  ];

  home.username = "mitac";
  home.homeDirectory = "/home/mitac";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
}
