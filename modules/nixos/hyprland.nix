{ pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    # Custom greetd wrappers launch via start-hyprland; keep UWSM off so stock
    # hyprland-uwsm.desktop stays out of the curated tuigreet list.
    withUWSM = false;
    xwayland.enable = true;
  };

  # Desktop-specific portals: Plasma uses KDE; Hyprland uses xdph + gtk.
  # Without this, both stacks fight under every session (duplicate D-Bus names,
  # "Could not register app ID" spam).
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-hyprland
    ];
    config = {
      common.default = [ "gtk" ];
      hyprland = {
        default = [
          "hyprland"
          "gtk"
        ];
      };
      kde = {
        default = [
          "kde"
          "gtk"
        ];
      };
    };
  };

  # Shared tooling for Caelestia-AW / end4-pC Hyprland sessions.
  # (Plasma brings its own stack; these stay inert there.)
  environment.systemPackages = with pkgs; [
    # Shell / bar
    quickshell
    # Clipboard + picker
    wl-clipboard
    cliphist
    hyprpicker
    # Screenshots / recording helpers used by end4 scripts
    grim
    slurp
    jq
    libnotify
    # Backlight / media keys
    brightnessctl
    playerctl
    # Theming helpers (end4 Material You pipeline; safe no-ops if unused)
    matugen
    # Wallpaper backends some widgets expect (nixpkgs renamed swww → awww)
    awww
    mpvpaper
    # Auth / secrets for shell prompts
    kdePackages.polkit-kde-agent-1
    libsecret
    # Fonts for Material Symbols UI in end4 / Caelestia
    material-symbols
    rubik
  ];
}
