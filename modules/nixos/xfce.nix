# Xfce as a selectable greetd Wayland session (labwc compositor).
{ ... }:

{
  # Do not enable a separate display manager — tuigreet remains the greeter.
  services.xserver.desktopManager.xfce = {
    enable = true;
    # Match Plasma/GNOME: Wayland-only in the curated tuigreet list.
    enableWaylandSession = true;
  };

  # Chromebook audio stays on PulseAudio; power-profiles-daemon stays off
  # (auto-cpufreq in chromebook/power.nix).
}
