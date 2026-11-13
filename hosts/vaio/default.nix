# VAIO laptop (Intel 8th+ gen iGPU) host configuration.
{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/common.nix
    ../../modules/nixos/desktop.nix
    ../../modules/nixos/laptop.nix
    ../../modules/nixos/vaio.nix
    ../../modules/nixos/backup.nix
    ../../modules/nixos/remote-builder.nix
    ../../modules/nixos/nix-ld.nix
    ../../modules/nixos/release.nix
  ];

  # Match the NixOS release from the first install on this machine.
  system.stateVersion = "26.05";
}
