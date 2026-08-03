# Sway: keyboard-first Wayland session (tuigreet-adjacent TUI feel).
{ pkgs, ... }:

{
  programs.sway = {
    enable = true;
    # Stock sway.desktop is curated into tuigreet; keep wrapper for dbus/env.
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      swaylock
      swayidle
      foot
      wl-clipboard
    ];
  };

  security.pam.services.swaylock.enable = true;

  # Chromebook audio stays on PulseAudio; power-profiles-daemon stays off.
}
