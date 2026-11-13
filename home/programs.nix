# Shared user programs and packages (Sway session).
{
  lib,
  pkgs,
  config,
  osConfig ? null,
  ...
}:

let
  email = "mitac31709@gmail.com";
  isPipewirePulse = osConfig != null && (osConfig.services.pipewire.pulse.enable or false);
  audioServiceAfter =
    if isPipewirePulse then
      [
        "pipewire-pulse.service"
        "wireplumber.service"
      ]
    else
      [ "pulseaudio.service" ];
  audioServiceRequires =
    if isPipewirePulse then [ "pipewire-pulse.service" ] else [ "pulseaudio.service" ];
  # Rasi unquoted value (same shape as config.lib.formats.rasi.mkLiteral).
  mkLiteral = value: {
    _type = "literal";
    inherit value;
  };

  # Windows 7 / Vista startup cue for paplay / PulseAudio (same Fripp boot sound).
  # Official Media/Windows Startup.wav in Win7 is a ~0.2s stub; this is the iconic one.
  windows7StartupWav = pkgs.fetchurl {
    url = "https://archive.org/download/10-.-wav/Vista%20.WAV.wav";
    name = "windows-7-startup.wav";
    hash = "sha256-fOaAm7YsloolLoknFqr1Tqh81p9gFkq+T17LFwRg8vM=";
  };

  ghostty = "${pkgs.ghostty}/bin/ghostty";
  yazi = "${pkgs.yazi}/bin/yazi";
  lazyPlugins = import ./lazy-plugins.nix { inherit pkgs lib; };
in
{
  # User identity. The system profile also ships git, without this
  # name/email, so root and a recovery shell can still run git.
  programs.git = {
    enable = true;
    settings.user = {
      name = "mitac";
      inherit email;
    };
  };

  # App launcher / dmenu: TUI look matching Sway (dark + cyan, monospace).
  programs.rofi = {
    enable = true;
    package = pkgs.rofi;
    settings = {
      terminal = "${pkgs.ghostty}/bin/ghostty";
      modes = "drun,run";
      font = "JetBrainsMono Nerd Font 12";
      show-icons = true;
      disable-history = false;
      sort = true;
      sorting-method = "fzf";
      case-sensitive = false;
      cycle = true;
      # comment must be listed here to appear in drun-display-format.
      drun-match-fields = "name,generic,exec,categories,keywords,comment";
      drun-display-format = "{name} <span weight='light' size='small' foreground='#6b7785'><i>{generic}</i>  {comment}</span>";
      drun-show-actions = true;
      display-drun = ">";
      display-run = "$";
      display-dmenu = ">";
      location = 0;
    };
    theme = {
      "*" = {
        bg = mkLiteral "#0b0f14";
        bg-alt = mkLiteral "#15383a";
        fg = mkLiteral "#e6edf3";
        fg-dim = mkLiteral "#6b7785";
        accent = mkLiteral "#33c5c5";
        urgent = mkLiteral "#e06c75";
        background-color = mkLiteral "transparent";
        text-color = mkLiteral "@fg";
      };

      "window" = {
        background-color = mkLiteral "@bg";
        border = mkLiteral "1px";
        border-color = mkLiteral "@accent";
        border-radius = mkLiteral "0";
        width = mkLiteral "56em";
        padding = mkLiteral "0.6em";
      };

      "mainbox" = {
        children = map mkLiteral [
          "inputbar"
          "message"
          "listview"
        ];
        spacing = mkLiteral "0.5em";
      };

      "inputbar" = {
        children = map mkLiteral [
          "prompt"
          "entry"
        ];
        spacing = mkLiteral "0.5em";
        background-color = mkLiteral "@bg";
        text-color = mkLiteral "@accent";
      };

      "prompt" = {
        text-color = mkLiteral "@accent";
        background-color = mkLiteral "@bg";
      };

      "entry" = {
        placeholder = "run…";
        placeholder-color = mkLiteral "@fg-dim";
        text-color = mkLiteral "@fg";
        background-color = mkLiteral "@bg";
        cursor = mkLiteral "text";
      };

      "listview" = {
        lines = 12;
        columns = 1;
        fixed-height = true;
        dynamic = true;
        scrollbar = true;
        spacing = mkLiteral "0.1em";
        background-color = mkLiteral "@bg";
      };

      "scrollbar" = {
        width = mkLiteral "0.3em";
        handle-color = mkLiteral "@accent";
        handle-width = mkLiteral "0.3em";
        background-color = mkLiteral "@bg";
      };

      "element" = {
        padding = mkLiteral "0.3em 0.4em";
        spacing = mkLiteral "0.6em";
        border-radius = mkLiteral "0";
        background-color = mkLiteral "@bg";
        text-color = mkLiteral "@fg";
        children = map mkLiteral [
          "element-icon"
          "element-text"
        ];
      };

      "element-icon" = {
        size = mkLiteral "1.5em";
        background-color = mkLiteral "inherit";
        text-color = mkLiteral "inherit";
      };

      "element-text" = {
        background-color = mkLiteral "inherit";
        text-color = mkLiteral "inherit";
        vertical-align = mkLiteral "0.5";
        markup = mkLiteral "true";
      };

      "element selected" = {
        background-color = mkLiteral "@bg-alt";
        text-color = mkLiteral "@accent";
      };

      "element alternate" = {
        background-color = mkLiteral "@bg";
        text-color = mkLiteral "@fg";
      };

      "element urgent" = {
        text-color = mkLiteral "@urgent";
      };

      "message" = {
        background-color = mkLiteral "@bg";
        border = mkLiteral "0";
        padding = mkLiteral "0";
      };

      "textbox" = {
        background-color = mkLiteral "@bg";
        text-color = mkLiteral "@fg-dim";
      };
    };
  };

  # GitHub CLI. gitCredentialHelper (default on) wires HTTPS push/pull to
  # `gh auth git-credential` so we never need to write ~/.config/git/config
  # (that path is a Home Manager → Nix store symlink on this host).
  programs.gh = {
    enable = true;
    settings.git_protocol = "https";
  };

  # prefer-dark so waybar does not treat the session as light (white modules).
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };

  # Stub: leftover light colors.css @import breaks waybar module chrome.
  xdg.configFile = lib.mkMerge [
    {
      "gtk-3.0/gtk.css".text = ''
        /* keep empty — light GTK sync breaks waybar module backgrounds */
      '';
      "gtk-4.0/gtk.css".text = ''
        /* keep empty — light GTK sync breaks waybar module backgrounds */
      '';
      "nvim".source = ./nvim;
    }
    (lib.mkIf (osConfig != null) {
      # Fcitx reads ~/.config/fcitx5 before /etc/xdg/fcitx5. These symlinks are the
      # same INI the NixOS module writes to /etc, so an old user copy (keyboard-jp,
      # Zenkaku as Trigger) cannot win. The store file is read-only: change the
      # input method in modules/nixos/common.nix, not in fcitx5-configtool.
      "fcitx5/profile" = {
        text = osConfig.environment.etc."xdg/fcitx5/profile".text;
        force = true;
      };
      "fcitx5/config" = {
        text = osConfig.environment.etc."xdg/fcitx5/config".text;
        force = true;
      };
    })
  ];

  # Bitwarden client (rbw). Holds the restic backup encryption key; see
  # modules/nixos/backup.nix. Log in once with `rbw login` after first switch.
  programs.rbw = {
    enable = true;
    settings = {
      inherit email;
      # Official Bitwarden EU cloud (defaults are .com / US).
      base_url = "https://api.bitwarden.eu";
      identity_url = "https://identity.bitwarden.eu";
      ui_url = "https://vault.bitwarden.eu";
      notifications_url = "https://notifications.bitwarden.eu";
      pinentry = pkgs.pinentry-qt;
      lock_timeout = 3600;
    };
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    # LazyVim plugins and treesitter parsers come from nixpkgs
    # (home/lazy-plugins.nix). Mason stays disabled. LSP / format / search
    # CLIs stay here; nvim does not download them.
    extraPackages = with pkgs; [
      ripgrep
      fd
      lua-language-server
      stylua
    ];
  };

  # Default terminal (Ctrl+Alt+T / Super+Return).
  programs.ghostty = {
    enable = true;
    settings = {
      font-family = "JetBrainsMono Nerd Font";
      font-size = 12;
      gtk-single-instance = true;
    };
  };

  home.sessionVariables = {
    TERMINAL = "ghostty";
    # Java AWT on Sway/i3: without this, frames often paint solid black.
    _JAVA_AWT_WM_NONREPARENTING = "1";
  };

  # Yazi via Ghostty for inode/directory mime (xdg-open etc.).
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

  systemd.user.services.windows-7-startup-sound = {
    Unit = {
      Description = "Windows 7 startup sound";
      After = audioServiceAfter ++ [ "graphical-session.target" ];
      Requires = audioServiceRequires;
    };
    Service = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
      ExecStart = "${pkgs.pulseaudio}/bin/paplay ${windows7StartupWav}";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Writable npm global prefix (store node/npm cannot install -g into itself).
  # Used for dsh / dsh-tui (`npm i -g @deepseek-ai/dsh @deepseek-harness-tui/dsh-tui`).
  # allow-scripts: native helpers (node-pty / koffi / spawn helper) needed at runtime.
  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm-global
    allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs
  '';

  home.sessionPath = [
    "${config.home.homeDirectory}/.npm-global/bin"
  ];

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

  # xdg.configFile."nvim".source is merged in xdg.configFile above.
  # Keep outside lazy's plugin root (~/.local/share/nvim/lazy/): a HM symlink
  # there is seen as uninstalled (Util.ls reports "link"), so lazy tries to
  # re-clone and fails with "should be a directory!". dev.path below is a
  # sibling directory of real directories (linkFarm), which lazy accepts.
  xdg.dataFile."nvim/nix/lazy.nvim".source = "${pkgs.vimPlugins.lazy-nvim}";
  xdg.dataFile."nvim/nix/plugins".source = lazyPlugins.plugins;
  xdg.dataFile."nvim/nix/treesitter".source = lazyPlugins.treesitter;

  # Terminal file manager (Sway: Super+e → Ghostty -e yazi).
  # Bash wrapper `y` cds into the last dir on quit.
  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    settings = {
      mgr = {
        show_hidden = true;
        show_symlink = true;
        sort_by = "natural";
        sort_dir_first = true;
        # mtime on the right; toggle with m+m / m+p / m+o inside Yazi.
        linemode = "mtime";
      };
      preview = {
        wrap = "yes";
        tab_size = 2;
      };
    };
  };

  home.packages = with pkgs; [
    btop
    nix-output-monitor
    # Cat clone with syntax highlighting (`bat`; Debian package name is batcat).
    bat
    # Steam Locomotive — joke for mistyping `ls`.
    sl
    # Download utility (command: aria2c).
    aria2
    # YouTube / media downloader.
    yt-dlp
    # Media file technical metadata.
    mediainfo
    # RTSP / local video player (`mpv`).
    mpv
    # ffmpeg + ffplay (RTSP probe / playback).
    ffmpeg
    # 7-Zip with Zstd/Brotli/LZ4/etc. (`7z` / `7zz`). Attribute starts with `_` (digit).
    _7zip-zstd
    # Archive manager GUI (7z / Zstd / zip / tar / …). Desktop: PeaZip.
    peazip
    code-cursor
    # Zed code editor (CLI: zeditor).
    zed-editor
    # Terminal Agent CLI (`cursor-agent`; also aliased as `agent`).
    cursor-cli
    # OpenCode 2 terminal agent (`opencode`; pkgs/opencode overrides nixpkgs 1.x).
    opencode
    # Anthropic Claude Code CLI (`claude`).
    claude-code
    # Google Antigravity CLI (`agy` / `antigravity`; pkgs/antigravity).
    antigravity
    # ChatGPT desktop (Codex included). App menu: ChatGPT.
    chatgpt
    # Grok Bot desktop agent. App menu: Grok Bot (`grok-bot`).
    grok-bot
    # Earthquake map (pkgs/jquake: Sway AWT fix + sounds cwd + http.agent).
    jquake
    onlyoffice-desktopeditors
    # 3D printer slicer (Bambu/Prusa fork). App menu: OrcaSlicer (`orca-slicer`).
    orca-slicer
    # Affinity v3 is not installed. The affinity-nix input and overlay were
    # removed. Re-add steps are in the README (Affinity). Wine builds often
    # take hours when cache.forall.systems misses.
    parsec-bin
    # Wineprefix manager for Windows apps/games (FHS-wrapped).
    (bottles.override { removeWarningPopup = true; })
    # wol-pc (Wake-on-LAN client): password SSH + GUI password prompt.
    # Scripts live in ~/Projects/wol-pc (not in the Nix store; config.env is local).
    sshpass
    zenity
    tmux
    trayscale
    vivaldi
    firefox
    # Tor Browser Bundle (not the tor daemon alone).
    tor-browser
    # On-screen keystroke overlay (useful for demos / Chromebook Fn keys).
    showmethekey
    # Google Quick Share / Nearby Share client for Linux.
    rquickshare
    discord
    # ESP32 / Arduino CLI flash & board package manager.
    arduino-cli
    # Espressif ROM / flash probe (chip-id, flash-id, …).
    esptool
    # Android screen mirror / control (GUI; wraps adb + scrcpy-server).
    qtscrcpy
    # adb / fastboot on PATH. QtScrcpy embeds its own adb, but the cheatsheet
    # runs `adb devices` as a separate command, so this package stays.
    android-tools
    # Node.js (`node` / `npm`) and pnpm (standalone binary; uses `node` on PATH).
    nodejs
    pnpm
    # Typst typesetting (CLI). Cursor uses the Tinymist extension for LSP/preview.
    typst
    tinymist
    typstyle
  ];
}
