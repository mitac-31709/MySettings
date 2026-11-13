# Sway: primary keyboard-first Wayland session (tuigreet-adjacent TUI feel).
{ pkgs, ... }:

{
  services.displayManager.defaultSession = "sway";

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    # swaylock stays on the system profile: its PAM stack is system-wide
    # (security.pam.services.swaylock below). waybar / rofi / mako are Home
    # Manager programs. cliphist, wl-clipboard, grim, slurp, swayidle,
    # brightnessctl, and jq are home.packages. Keybinds use those same store
    # paths, so each command is linked once. wlrctl was not referenced.
    extraPackages = with pkgs; [
      swaylock
    ];
  };

  security.pam.services.swaylock.enable = true;

  # Audio (PulseAudio on Chromebook, PipeWire on VAIO) and power-profiles-daemon stay host-managed.
}
