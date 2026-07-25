{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/common.nix
    ../../modules/nixos/gnome.nix
  ];

  # Adjust to match the NixOS release used on first install if needed.
  system.stateVersion = "25.05";
}
