# Plasma-specific Home Manager: align defaults/shortcuts with the Sway stack.
{
  pkgs,
  lib,
  ...
}:

let
  # Classic Windows XP startup cue for paplay / PulseAudio.
  # myinstants started returning 403; use the Internet Archive mirror instead.
  windowsXpStartupWav = pkgs.fetchurl {
    url = "https://archive.org/download/windowsxpstartup_201910/Windows%20XP%20Startup.wav";
    hash = "sha256-j4Weu5AkcDbO0R24VISKvhQ03D/9+leV98XwbbmkI9U=";
  };

  ghostty = "${pkgs.ghostty}/bin/ghostty";
  yazi = "${pkgs.yazi}/bin/yazi";
  grim = "${pkgs.grim}/bin/grim";
  slurp = "${pkgs.slurp}/bin/slurp";
  wlCopy = "${pkgs.wl-clipboard}/bin/wl-copy";
  rofi = "${pkgs.rofi}/bin/rofi";

  grimFull = pkgs.writeShellScript "mitac-grim-full" ''
    ${grim} - | ${wlCopy}
  '';
  grimRegion = pkgs.writeShellScript "mitac-grim-region" ''
    ${grim} -g "$(${slurp})" - | ${wlCopy}
  '';
in
{
  # NumLock on at Plasma startup (0 = on).
  # Touchpad: traditional scrolling; keep pointer active while typing.
  # ClickMethod=2 = clickfinger. Libinput section: delbin Elan Touchpad.
  xdg.configFile."kcminputrc".text = ''
    [Keyboard]
    NumLock=0

    [Libinput/1267/194/Elan Touchpad]
    ClickMethod=2
    DisableWhileTyping=false
    NaturalScroll=false
    TapToClick=true
  '';

  # Plasma XDG autostart also tries to spawn pulseaudio while systemd already
  # runs pulseaudio.service → app-pulseaudio@autostart.service exit-code.
  xdg.configFile."autostart/pulseaudio.desktop".text = ''
    [Desktop Entry]
    Hidden=true
  '';

  # Prefer cliphist (shared with Sway) over Klipper.
  xdg.configFile."autostart/org.kde.klipper.desktop".text = ''
    [Desktop Entry]
    Hidden=true
  '';

  # Prefer explicit Ghostty wrappers so Plasma never falls back to a missing Konsole.
  xdg.dataFile."applications/mitac-yazi.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Yazi
    Comment=Terminal file manager (Ghostty)
    Exec=${ghostty} -e ${yazi} %U
    Icon=yazi
    Terminal=false
    Categories=System;FileManager;FileTools;
    MimeType=inode/directory;
    StartupNotify=true
  '';

  xdg.dataFile."applications/mitac-rofi.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=rofi
    Comment=Application launcher
    Exec=${rofi} -show drun
    Icon=system-search
    Terminal=false
    Categories=Utility;
    NoDisplay=true
    StartupNotify=false
  '';

  xdg.dataFile."applications/mitac-clipboard-history.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Clipboard History
    Comment=cliphist + rofi picker
    Exec=clipboard-history
    Icon=edit-paste
    Terminal=false
    Categories=Utility;
    NoDisplay=true
    StartupNotify=false
  '';

  xdg.dataFile."applications/mitac-grim-full.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Screenshot (full)
    Comment=grim → clipboard
    Exec=${grimFull}
    Icon=applets-screenshooter
    Terminal=false
    Categories=Utility;
    NoDisplay=true
    StartupNotify=false
  '';

  xdg.dataFile."applications/mitac-grim-region.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Screenshot (region)
    Comment=grim+slurp → clipboard
    Exec=${grimRegion}
    Icon=applets-screenshooter
    Terminal=false
    Categories=Utility;
    NoDisplay=true
    StartupNotify=false
  '';

  # Default apps match the Sway stack (browser already Vivaldi via user mimeapps).
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = [ "mitac-yazi.desktop" ];
      "text/plain" = [ "nvim.desktop" ];
      "text/markdown" = [ "nvim.desktop" ];
      "text/x-cmake" = [ "nvim.desktop" ];
      "application/json" = [ "nvim.desktop" ];
      "application/x-shellscript" = [ "nvim.desktop" ];
      "application/zip" = [ "peazip.desktop" ];
      "application/x-7z-compressed" = [ "peazip.desktop" ];
      "application/x-tar" = [ "peazip.desktop" ];
      "application/gzip" = [ "peazip.desktop" ];
      "application/x-xz" = [ "peazip.desktop" ];
      "application/x-rar" = [ "peazip.desktop" ];
      "application/vnd.rar" = [ "peazip.desktop" ];
      "text/html" = [ "vivaldi-stable.desktop" ];
      "x-scheme-handler/http" = [ "vivaldi-stable.desktop" ];
      "x-scheme-handler/https" = [ "vivaldi-stable.desktop" ];
      "x-scheme-handler/about" = [ "vivaldi-stable.desktop" ];
      "x-scheme-handler/unknown" = [ "vivaldi-stable.desktop" ];
    };
  };

  # Merge into shared KConfig (don't replace whole files).
  home.activation.plasmaDesktopPrefs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    kwriteconfig6=${pkgs.kdePackages.kconfig}/bin/kwriteconfig6
    $kwriteconfig6 --file kdeglobals --group General --key fixed \
      "JetBrainsMono Nerd Font,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    $kwriteconfig6 --file kdeglobals --group General --key TerminalApplication ghostty
    $kwriteconfig6 --file kdeglobals --group General --key TerminalService \
      com.mitchellh.ghostty.desktop

    # Terminal: Ghostty (not Konsole).
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group com.mitchellh.ghostty.desktop \
      --key _launch "Ctrl+Alt+T"

    # Launcher: rofi (Sway parity). Keep Alt+F2 on KRunner for Plasma settings search.
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group mitac-rofi.desktop \
      --key _launch "Meta+R	Alt+Space"
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group org.kde.krunner.desktop \
      --key _launch "Alt+F2	Search"

    # File manager: Yazi in Ghostty (Super+E, same as Sway).
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group mitac-yazi.desktop \
      --key _launch "Meta+E"

    # Clipboard: cliphist+rofi (not Klipper).
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group mitac-clipboard-history.desktop \
      --key _launch "Meta+V"
    $kwriteconfig6 --file kglobalshortcutsrc --group klipper \
      --key "show clipboard items at mouse position" "none,none,クリップボードの履歴を表示する" || true

    # Screenshots: grim / grim+slurp (not Spectacle).
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group mitac-grim-full.desktop \
      --key _launch "Print"
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group mitac-grim-region.desktop \
      --key _launch "Meta+Shift+S"

    # Lock / leave (unchanged parity).
    $kwriteconfig6 --file kglobalshortcutsrc --group ksmserver \
      --key "Lock Session" "Meta+L,Meta+L,スクリーンをロック"
    $kwriteconfig6 --file kglobalshortcutsrc --group ksmserver \
      --key "Log Out" "Ctrl+Alt+Del	Screensaver,Ctrl+Alt+Del,ログアウト画面を表示"
  '';

  # Plays on every graphical session (Sway / Plasma).
  systemd.user.services.windows-xp-startup-sound = {
    Unit = {
      Description = "Windows XP startup sound";
      After = [
        "pulseaudio.service"
        "graphical-session.target"
      ];
      Requires = [ "pulseaudio.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
      ExecStart = "${pkgs.pulseaudio}/bin/paplay ${windowsXpStartupWav}";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
