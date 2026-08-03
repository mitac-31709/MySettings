{ ... }:

{
  services.desktopManager.plasma6.enable = true;
  # Session chooser is greetd+tuigreet (see greetd.nix); keep Plasma as a
  # selectable Wayland desktop only (no Plasma X11 / startx).
  services.displayManager.plasma-login-manager.enable = false;
}
