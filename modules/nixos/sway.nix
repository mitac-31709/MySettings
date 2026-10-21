# Sway: primary keyboard-first Wayland session (tuigreet-adjacent TUI feel).
{ pkgs, ... }:

{
  services.displayManager.defaultSession = "sway";

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      swaylock
      swayidle
      wl-clipboard
      waybar
      mako
      grim
      slurp
      wlrctl
      brightnessctl
      cliphist
      rofi
      jq
    ];
  };

  security.pam.services.swaylock.enable = true;

  # Chromebook audio stays on PulseAudio; power-profiles-daemon stays off.
}
