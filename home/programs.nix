# Shared user programs and packages (all sessions).
{ lib, pkgs, ... }:

let
  email = "mitac31709@gmail.com";
  # Rasi unquoted value (same shape as config.lib.formats.rasi.mkLiteral).
  mkLiteral = value: {
    _type = "literal";
    inherit value;
  };
in
{
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

  # prefer-dark: Plasma sometimes leaves prefer-light + a light colors.css, which
  # makes waybar discover appearance "light" and flash white on battery/etc.
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };

  # Do not @import Plasma's light colors.css (theme_base #fff). Plasma may
  # rewrite these on a Plasma login; next HM switch restores the stub.
  xdg.configFile."gtk-3.0/gtk.css".text = ''
    /* no Plasma colors.css — light sync breaks waybar module backgrounds */
  '';
  xdg.configFile."gtk-4.0/gtk.css".text = ''
    /* no Plasma colors.css — light sync breaks waybar module backgrounds */
  '';

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
    # Plugins are managed by LazyVim / lazy.nvim (see ./nvim), not Home Manager.
    # Mason is disabled under NixOS; put LSP / format / search CLIs here instead.
    extraPackages = with pkgs; [
      ripgrep
      fd
      gcc # treesitter parser builds
      tree-sitter # nvim-treesitter CLI requirement
      lua-language-server
      stylua
    ];
  };

  # Default terminal across Sway / Plasma.
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

  # Fcitx5 prefers ~/.config over /etc/xdg. Keep the declarative profile /
  # config (Meltype first, TriggerKeys, ShareInputState) from being overwritten
  # by an older user copy (e.g. keyboard-jp + Zenkaku as Trigger).
  home.activation.syncFcitx5Profile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/fcitx5"
    if [ -f /etc/xdg/fcitx5/profile ]; then
      cp -f /etc/xdg/fcitx5/profile "$HOME/.config/fcitx5/profile"
    fi
    if [ -f /etc/xdg/fcitx5/config ]; then
      cp -f /etc/xdg/fcitx5/config "$HOME/.config/fcitx5/config"
    fi
  '';

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

  xdg.configFile."nvim".source = ./nvim;
  # Keep outside lazy's plugin root (~/.local/share/nvim/lazy/): a HM symlink
  # there is seen as uninstalled (Util.ls reports "link"), so lazy tries to
  # re-clone and fails with "should be a directory!".
  xdg.dataFile."nvim/nix/lazy.nvim".source = "${pkgs.vimPlugins.lazy-nvim}";

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
    # 7-Zip with Zstd/Brotli/LZ4/etc. (`7z` / `7zz`). Attribute starts with `_` (digit).
    _7zip-zstd
    # Archive manager GUI (7z / Zstd / zip / tar / …). Desktop: PeaZip.
    peazip
    code-cursor
    # Terminal Agent CLI (`cursor-agent`; also aliased as `agent`).
    cursor-cli
    # ChatGPT desktop (Codex included). App menu: ChatGPT.
    chatgpt
    # Grok Bot desktop agent. App menu: Grok Bot (`grok-bot`).
    grok-bot
    # Earthquake map (pkgs/jquake: Sway AWT fix + sounds cwd + http.agent).
    jquake
    onlyoffice-desktopeditors
    # Affinity v3 omitted: affinity-nix patches wineWow64 and often
    # source-builds for hours when cache.forall.systems misses.
    # Re-enable with: affinity-v3
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
    # Standalone adb / fastboot CLI (QtScrcpy also embeds adb).
    android-tools
    # Node.js (`node` / `npm`) and pnpm (standalone binary; uses `node` on PATH).
    nodejs
    pnpm
  ];
}
