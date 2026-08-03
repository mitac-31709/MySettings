# Sway: primary keyboard-first Wayland session (tuigreet-adjacent TUI feel).
{ pkgs, ... }:

{
  programs.sway = {
    enable = true;
    # Stock sway.desktop is curated into tuigreet as 00-sway; keep wrapper for dbus/env.
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      swaylock
      swayidle
      wl-clipboard
      waybar
      mako
      grim
      slurp
      brightnessctl
      cliphist
      rofi
    ];
  };

  security.pam.services.swaylock.enable = true;

  # Chromebook audio stays on PulseAudio; power-profiles-daemon stays off.
}
