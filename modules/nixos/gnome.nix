{ pkgs, ... }:

{
  # GNOME as a selectable greetd session alongside Plasma / Hyprland.
  # Do not enable GDM — tuigreet remains the login greeter.
  services.desktopManager.gnome.enable = true;
  services.displayManager.gdm.enable = false;

  # Chromebook audio stays on PulseAudio (see plasma.nix). GNOME works with
  # Pulse; do not flip PipeWire audio back on for sof-rt5682.
  # power-profiles-daemon stays off (auto-cpufreq in plasma.nix).

  environment.systemPackages = with pkgs; [
    gnome-tweaks
  ];
}
