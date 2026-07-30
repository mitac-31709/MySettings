{ pkgs, lib, ... }:

{
  programs.hyprland = {
    enable = true;
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

  # end4-pC / Illogical Impulse Quickshell needs Qt5Compat.GraphicalEffects under
  # Hyprland. Plasma injects QML paths; bare Hyprland does not
  # (https://github.com/end-4/dots-hyprland/issues/1750).
  environment.systemPackages = with pkgs; [
    quickshell
    kdePackages.qt5compat
    kdePackages.qtpositioning
    kdePackages.qtmultimedia
    kdePackages.qtimageformats
    wl-clipboard
    hyprpicker
    cliphist
    hypridle
    hyprsunset
    brightnessctl
    bibata-cursors
    python3
  ];

  # Prepend QML modules for qs. Plasma sessions usually already provide a
  # richer path; mkDefault lets DE modules override if needed.
  environment.sessionVariables.QML2_IMPORT_PATH = lib.mkDefault (
    lib.concatStringsSep ":" [
      "${pkgs.kdePackages.qt5compat}/lib/qt-6/qml"
      "${pkgs.kdePackages.qtpositioning}/lib/qt-6/qml"
      "${pkgs.kdePackages.qtmultimedia}/lib/qt-6/qml"
      "${pkgs.kdePackages.qtimageformats}/lib/qt-6/qml"
    ]
  );
}
