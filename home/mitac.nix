{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

let
  # Absolute flake path so `rebuild` works from $HOME (or any cwd), not only
  # when the shell is already inside the MySettings checkout.
  flakeUri = "${config.home.homeDirectory}/MySettings#mitac";

  # Classic Windows XP startup cue (personal desktop flair). Converted to WAV
  # so paplay can play it through PulseAudio after login.
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

  # Minimal Hyprland configs for dedicated greetd sessions.
  hyprlandCaelestiaConf = ''
    monitor=,preferred,auto,1

    exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
    exec-once = caelestia shell -d

    input {
      kb_layout = jp
      follow_mouse = 1
      touchpad {
        natural_scroll = false
        tap-to-click = true
      }
    }

    general {
      gaps_in = 4
      gaps_out = 8
      border_size = 2
    }

    decoration {
      rounding = 8
    }

    bind = SUPER, Return, exec, ${pkgs.kdePackages.konsole}/bin/konsole
    bind = SUPER, Q, killactive,
    bind = SUPER SHIFT, E, exit,
    bind = SUPER, F, fullscreen,
    bind = SUPER, Space, exec, caelestia shell drawers toggle launcher
  '';

  hyprlandEnd4Conf = ''
    monitor=,preferred,auto,1

    exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
    exec-once = qs -c end4-pC

    input {
      kb_layout = jp
      follow_mouse = 1
      touchpad {
        natural_scroll = false
        tap-to-click = true
      }
    }

    general {
      gaps_in = 4
      gaps_out = 8
      border_size = 2
    }

    decoration {
      rounding = 8
    }

    bind = SUPER, Return, exec, ${pkgs.kdePackages.konsole}/bin/konsole
    bind = SUPER, Q, killactive,
    bind = SUPER SHIFT, E, exit,
    bind = SUPER, F, fullscreen,
    bind = SUPER, Escape, global, quickshell:settingsToggle
  '';
in
{
  imports = [
    inputs.caelestia-shell-aw.homeManagerModules.default
  ];

  home.username = "mitac";
  home.homeDirectory = "/home/mitac";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  # Caelestia-AW: package + CLI on PATH. Start from Hyprland exec-once, not under
  # every graphical-session (would also fire on Plasma).
  programs.caelestia = {
    enable = true;
    systemd.enable = false;
    cli.enable = true;
    settings = {
      paths.wallpaperDir = "~/Pictures/Wallpapers";
    };
  };

  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "ls -la";
      rebuild = "sudo nixos-rebuild switch --flake ${flakeUri}";
      generations = "nixos-rebuild list-generations";
      # Emergency: stop looping SOF amp playback (Broken pipe / stuck buffer).
      audio-panic = "amixer -c 0 sset 'Left Digital' 0% && amixer -c 0 sset 'Right Digital' 0% && amixer -c 0 sset 'Left Spk' off && amixer -c 0 sset 'Right Spk' off && systemctl --user restart pulseaudio.service 2>/dev/null; systemctl --user restart pipewire.service wireplumber.service 2>/dev/null; true";
      # Console session: wrap common GUI apps with cage when no display is up.
      firefox = "gui firefox";
      vivaldi = "gui vivaldi";
      cursor = "gui cursor";
      code-cursor = "gui cursor";
      onlyoffice-desktopeditors = "gui onlyoffice-desktopeditors";
      jquake = "gui jquake";
      parsec = "gui parsecd";
      trayscale = "gui trayscale";
    };
    # Top ~10 lines: command output; bottom: btop. Usage: runbtop <cmd> [args...]
    initExtra = ''
      runbtop() {
        if [ "$#" -eq 0 ]; then
          printf 'usage: runbtop <command> [args...]\n' >&2
          return 1
        fi
        tmux new-session \; \
          send-keys -- "$(printf '%q ' "$@")" C-m \; \
          split-window -v -- btop \; \
          select-pane -t '{top}' \; \
          resize-pane -y 10 \; \
          select-pane -t '{bottom}'
      }
    '';
  };

  programs.git = {
    enable = true;
    # Update these to your own identity.
    settings.user = {
      name = "mitac";
      email = "mitac31709@gmail.com";
    };
  };

  # Bitwarden client (rbw). Holds the restic backup encryption key; see
  # modules/nixos/backup.nix. Log in once with `rbw login` after first switch.
  programs.rbw = {
    enable = true;
    settings = {
      email = "mitac31709@gmail.com";
      # Official Bitwarden EU cloud (defaults are .com / US).
      # No trailing slashes — rbw is picky about these.
      base_url = "https://api.bitwarden.eu";
      identity_url = "https://identity.bitwarden.eu";
      ui_url = "https://vault.bitwarden.eu";
      notifications_url = "https://notifications.bitwarden.eu";
      # Qt pinentry for Plasma.
      pinentry = pkgs.pinentry-qt;
      lock_timeout = 3600;
    };
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    # Plugins are managed by lazy.nvim (see ./nvim), not Home Manager.
  };

  # Keep XDG dirs in English even with ja_JP.UTF-8 locale.
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    desktop = "$HOME/Desktop";
    documents = "$HOME/Documents";
    download = "$HOME/Downloads";
    music = "$HOME/Music";
    pictures = "$HOME/Pictures";
    publicShare = "$HOME/Public";
    templates = "$HOME/Templates";
    videos = "$HOME/Videos";
    extraConfig = {
      XDG_PROJECTS_DIR = "$HOME/Projects";
    };
  };

  # NumLock on at Plasma startup (0 = on, 1 = off, 2 = leave unchanged).
  # Touchpad: traditional scrolling; keep pointer active while typing.
  # ClickMethod=2 = clickfinger (1/2/3 fingers = left/right/middle), not button areas.
  # Libinput section is for delbin's Elan Touchpad (0x04f3:0x00c2).
  xdg.configFile."kcminputrc".text = ''
    [Keyboard]
    NumLock=0

    [Libinput/1267/194/Elan Touchpad]
    ClickMethod=2
    DisableWhileTyping=false
    NaturalScroll=false
    TapToClick=true
  '';

  # Konsole default profile: JetBrainsMono Nerd Font 12 (was GNOME Console dconf).
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

  # Neovim config → ~/.config/nvim
  xdg.configFile."nvim".source = ./nvim;

  # Bundle lazy.nvim from nixpkgs (no git clone bootstrap).
  xdg.dataFile."nvim/lazy/lazy.nvim".source = "${pkgs.vimPlugins.lazy-nvim}";

  # Hyprland session configs (selected via greetd: Caelestia-AW / end4-pC).
  xdg.configFile."hypr/caelestia.conf".text = hyprlandCaelestiaConf;
  xdg.configFile."hypr/end4.conf".text = hyprlandEnd4Conf;

  # end4-pC Quickshell config (does not overwrite other qs configs).
  xdg.configFile."quickshell/end4-pC".source = inputs.end4-pc;

  # Plasma settings that live in shared KConfig files (merge, don't replace).
  # - fixed font: system monospace (was org/gnome/desktop/interface)
  # - Ctrl+Alt+T → Konsole (was GNOME Console / kgx custom keybinding)
  # - Chromebook lock key (XF86ScreenSaver): show leave dialog instead of
  #   locking immediately (Meta+L still locks on purpose).
  home.activation.plasmaDesktopPrefs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    kwriteconfig6=${pkgs.kdePackages.kconfig}/bin/kwriteconfig6
    $kwriteconfig6 --file kdeglobals --group General --key fixed \
      "JetBrainsMono Nerd Font,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group org.kde.konsole.desktop \
      --key _launch "Ctrl+Alt+T"
    $kwriteconfig6 --file kglobalshortcutsrc --group ksmserver \
      --key "Lock Session" "Meta+L,Meta+L,スクリーンをロック"
    $kwriteconfig6 --file kglobalshortcutsrc --group ksmserver \
      --key "Log Out" "Ctrl+Alt+Del	Screensaver,Ctrl+Alt+Del,ログアウト画面を表示"
  '';

  # Ensure Caelestia animated-wallpaper directory exists.
  home.activation.caelestiaWallpaperDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${config.home.homeDirectory}/Pictures/Wallpapers/Animated"
  '';

  # Play Windows XP startup sound once Plasma/PulseAudio are up.
  # Sleep gives sof-rt5682 / speaker sink a moment after session start.
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

  home.packages = with pkgs; [
    btop
    firefox
    code-cursor
    # Pin 1.8.4 (nixpkgs currently ships 1.8.5). Same upstream zip layout.
    (jquake.overrideAttrs (_old: {
      version = "1.8.4";
      src = fetchurl {
        url = "https://github.com/fleneindre/fleneindre.github.io/raw/master/downloads/JQuake_1.8.4_linux.zip";
        hash = "sha256-oIYkYmI8uG4zjnm1Jq1mzIcSwRlKbWJqvACygQyp9sA=";
      };
    }))
    onlyoffice-desktopeditors
    parsec-bin
    tmux
    trayscale
    vivaldi
    # Caelestia-AW video wallpaper thumbnails / decode helpers
    ffmpeg
    python3Packages.pillow
  ];
}
