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

  # ~8 GiB RAM, no disk swap partition, tight root (Chromebook leftover
  # partitions). zram at 100% of RAM ≈ 8 GiB compressed swap (zstd); avoids
  # a swapfile on the ~90G root while giving headroom for Plasma + browsers.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
    algorithm = "zstd";
  };

  # zram-friendly VM knobs: swap earlier into cheap compressed RAM, avoid
  # reading ahead multiple pages from zram (page-cluster=0).
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
    "vm.vfs_cache_pressure" = 50;
  };

  # Match the NixOS release from the first install on this machine.
  system.stateVersion = "26.05";
}
