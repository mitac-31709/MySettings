{ pkgs, ... }:

{
  services.desktopManager.plasma6.enable = true;
  # Session chooser is greetd+tuigreet (see greetd.nix); keep Plasma as a
  # selectable Wayland desktop only (no Plasma X11 / startx).
  services.displayManager.plasma-login-manager.enable = false;

  # Prefer Sway-stack apps (Ghostty / Yazi / nvim / PeaZip / grim) over stock
  # Plasma utilities. Shell chrome (System Settings, etc.) stays.
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    konsole
    kate
    ark
    dolphin
    baloo-widgets
    dolphin-plugins
    spectacle
    elisa
    gwenview
    okular
    khelpcenter
    krdp
    # kwin-x11 removed upstream (EOL); Plasma here is Wayland-only anyway.
  ];
}
