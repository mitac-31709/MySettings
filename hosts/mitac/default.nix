{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/common.nix
    ../../modules/nixos/plasma.nix
    ../../modules/nixos/chromebook.nix
    ../../modules/nixos/backup.nix
    ../../modules/nixos/release.nix
  ];

  # ~8 GiB RAM, no disk swap partition, tight root (Chromebook leftover
  # partitions). zram at 100% of RAM ≈ 8 GiB compressed swap (zstd); avoids
  # a swapfile on the ~90G root while giving headroom for Plasma + browsers.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  # Match the NixOS release from the first install on this machine.
  system.stateVersion = "26.05";
}
