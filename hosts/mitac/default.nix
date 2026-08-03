{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/common.nix
    ../../modules/nixos/desktop.nix
    ../../modules/nixos/chromebook.nix
    ../../modules/nixos/backup.nix
    ../../modules/nixos/release.nix
  ];

  # Match the NixOS release from the first install on this machine.
  system.stateVersion = "26.05";
}
