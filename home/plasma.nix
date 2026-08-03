# Plasma-specific Home Manager settings (input, Konsole, shortcuts, flair).
{
  pkgs,
  lib,
  ...
}:

let
  # Classic Windows XP startup cue. Converted to WAV for paplay / PulseAudio.
  windowsXpStartupMp3 = pkgs.fetchurl {
    url = "https://www.myinstants.com/media/sounds/windows-xp-startup.mp3";
    hash = "sha256-xswjAInX8eq89eIjQ8VyuGkhEboVRAT2r0Rms4Kdnzo=";
  };
  windowsXpStartupWav =
    pkgs.runCommand "windows-xp-startup.wav"
      {
        nativeBuildInputs = [ pkgs.ffmpeg ];
      }
      ''
        ffmpeg -y -i ${windowsXpStartupMp3} -ar 44100 -ac 2 $out
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
  # - fixed font / Ctrl+Alt+T → Konsole / Chromebook lock key → leave dialog
  # - Meta+R → KRunner (search bar; matches Super+R on other sessions)
  home.activation.plasmaDesktopPrefs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    kwriteconfig6=${pkgs.kdePackages.kconfig}/bin/kwriteconfig6
    $kwriteconfig6 --file kdeglobals --group General --key fixed \
      "JetBrainsMono Nerd Font,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group org.kde.konsole.desktop \
      --key _launch "Ctrl+Alt+T"
    # Keep stock Alt+Space / Alt+F2 / Search; add Meta+R for cross-session parity.
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group org.kde.krunner.desktop \
      --key _launch "Meta+R	Alt+Space	Alt+F2	Search"
    $kwriteconfig6 --file kglobalshortcutsrc --group ksmserver \
      --key "Lock Session" "Meta+L,Meta+L,スクリーンをロック"
    $kwriteconfig6 --file kglobalshortcutsrc --group ksmserver \
      --key "Log Out" "Ctrl+Alt+Del	Screensaver,Ctrl+Alt+Del,ログアウト画面を表示"
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
