{
  pkgs,
  lib,
  config,
  ...
}:

let
  # QML modules needed by end4-pC / Illogical Impulse under bare Hyprland.
  # Plasma already exposes these via /run/current-system/sw; Hyprland sessions
  # still need the packages installed and QML2_IMPORT_PATH pointing at sw.
  # Refs: https://github.com/end-4/dots-hyprland/issues/1750
  #       https://discourse.nixos.org/t/export-qml2-import-path-qml2-import-path/73564
  qsQtDeps = with pkgs.kdePackages; [
    qt5compat
    qtpositioning
    qtmultimedia
    qtimageformats
    syntax-highlighting
    kirigami
  ];
in
{
  options.mitac.hyprland.qmlImportPath = lib.mkOption {
    type = lib.types.str;
    default = "/run/current-system/sw/lib/qt-6/qml";
    description = "QML2_IMPORT_PATH used by Hyprland sessions and greetd wrappers.";
  };

  config = {
    programs.hyprland = {
      enable = true;
      # Custom greetd wrappers launch via start-hyprland; keep UWSM off so stock
      # hyprland-uwsm.desktop stays out of the curated tuigreet list.
      withUWSM = false;
      xwayland.enable = true;
    };

    # Desktop-specific portals: Plasma=KDE, GNOME=gnome, Hyprland=xdph+gtk.
    # Without this, stacks fight under every session (duplicate D-Bus names,
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
        gnome = {
          default = [
            "gnome"
            "gtk"
          ];
        };
      };
    };

    environment.systemPackages = [
      pkgs.quickshell
    ]
    ++ qsQtDeps
    ++ (with pkgs; [
      # Clipboard + picker
      wl-clipboard
      cliphist
      hyprpicker
      # Screenshots / recording helpers used by end4 scripts
      grim
      slurp
      jq
      libnotify
      # Idle / night light (II hyprland.start)
      hypridle
      hyprsunset
      # Backlight / media keys
      brightnessctl
      playerctl
      # Theming helpers (end4 Material You pipeline; safe no-ops if unused)
      matugen
      # Wallpaper backends (nixpkgs renamed swww → awww)
      awww
      mpvpaper
      # Auth / secrets for shell prompts
      kdePackages.polkit-kde-agent-1
      libsecret
      # Fonts / cursors for Material UI in end4 / Caelestia
      material-symbols
      rubik
      bibata-cursors
      python3
    ]);

    # Prefer the aggregated system QML tree so every kdePackages.* we install
    # is visible, instead of listing individual store paths (easy to miss one).
    environment.sessionVariables.QML2_IMPORT_PATH = lib.mkDefault config.mitac.hyprland.qmlImportPath;
  };
}
