# Plasma-specific Home Manager settings (input, Konsole, shortcuts, flair).
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

  xdg.configFile."konsolerc".text = ''
    [Desktop Entry]
    DefaultProfile=Mitac.profile

    [General]
    ConfigVersion=1
  '';

  xdg.dataFile."konsole/Mitac.profile".text = ''
    [Appearance]
    Font=JetBrainsMono Nerd Font,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1

    [General]
    Name=Mitac
    Parent=FALLBACK/
  '';

  # Plasma XDG autostart also tries to spawn pulseaudio while systemd already
  # runs pulseaudio.service → app-pulseaudio@autostart.service exit-code.
  xdg.configFile."autostart/pulseaudio.desktop".text = ''
    [Desktop Entry]
    Hidden=true
  '';

  # Merge into shared KConfig (don't replace whole files).
  # - fixed font / Ctrl+Alt+T → Ghostty / Chromebook lock key → leave dialog
  # - Meta+R → KRunner (search bar; matches Super+R on other sessions)
  home.activation.plasmaDesktopPrefs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    kwriteconfig6=${pkgs.kdePackages.kconfig}/bin/kwriteconfig6
    $kwriteconfig6 --file kdeglobals --group General --key fixed \
      "JetBrainsMono Nerd Font,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    # Free Ctrl+Alt+T from Konsole; bind Ghostty (also declared on its .desktop).
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group org.kde.konsole.desktop \
      --key _launch "none"
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group com.mitchellh.ghostty.desktop \
      --key _launch "Ctrl+Alt+T"
    # Keep stock Alt+Space / Alt+F2 / Search; add Meta+R for cross-session parity.
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group org.kde.krunner.desktop \
      --key _launch "Meta+R	Alt+Space	Alt+F2	Search"
    $kwriteconfig6 --file kglobalshortcutsrc --group ksmserver \
      --key "Lock Session" "Meta+L,Meta+L,スクリーンをロック"
    $kwriteconfig6 --file kglobalshortcutsrc --group ksmserver \
      --key "Log Out" "Ctrl+Alt+Del	Screensaver,Ctrl+Alt+Del,ログアウト画面を表示"
    # Klipper: keep history and ensure Meta+V opens the popup.
    $kwriteconfig6 --file klipperrc --group General --key KeepClipboardContents true
    $kwriteconfig6 --file klipperrc --group General --key MaxClipItems 50
    $kwriteconfig6 --file klipperrc --group General --key IgnoreEmptyClipboard true
    $kwriteconfig6 --file kglobalshortcutsrc --group klipper \
      --key "show clipboard items at mouse position" "Meta+V,none,クリップボードの履歴を表示する"
  '';

  # Scoped to KDE so Hyprland sessions do not play it.
  systemd.user.services.windows-xp-startup-sound = {
    Unit = {
      Description = "Windows XP startup sound";
      After = [
        "pulseaudio.service"
        "graphical-session.target"
      ];
      Requires = [ "pulseaudio.service" ];
      ConditionEnvironment = "XDG_CURRENT_DESKTOP=KDE";
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
