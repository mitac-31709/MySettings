# Shared laptop power management: zram, thermald, auto-cpufreq, power-chords.
{ ... }:

{
  imports = [ ./power-chords.nix ];

  # zram at 100% of RAM (zstd) gives compressed memory swap without a swapfile.
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

  # Sustained performance under Intel laptop thermal limits.
  services.thermald.enable = true;

  # auto-cpufreq manages governors/turbo; conflicts with power-profiles-daemon.
  services.power-profiles-daemon.enable = false;
  services.auto-cpufreq = {
    enable = true;
    settings = {
      charger = {
        governor = "performance";
        turbo = "auto";
      };
      battery = {
        governor = "powersave";
        turbo = "auto";
      };
    };
  };
}
