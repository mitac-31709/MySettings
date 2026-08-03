{ pkgs, lib, ... }:

{
  # GNOME as a selectable greetd session alongside Plasma / Hyprland.
  # Do not enable GDM — tuigreet remains the login greeter.
  services.desktopManager.gnome.enable = true;
  services.displayManager.gdm.enable = false;

  # Chromebook audio stays on PulseAudio (see chromebook/audio.nix). GNOME
  # works with Pulse; do not flip PipeWire audio back on for sof-rt5682.
  # power-profiles-daemon stays off (auto-cpufreq in chromebook/power.nix).

  # Plasma6 and Seahorse (GNOME core-apps) both set askPassword at the same
  # priority; keep Plasma's helper as the system default.
  programs.ssh.askPassword = lib.mkForce (lib.getExe pkgs.kdePackages.ksshaskpass);

  environment.systemPackages = with pkgs; [
    gnome-tweaks
  ];
}
