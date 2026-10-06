# Shared user programs and packages (all sessions).
{ pkgs, ... }:

let
  email = "mitac31709@gmail.com";
in
{
  programs.git = {
    enable = true;
    settings.user = {
      name = "mitac";
      inherit email;
    };
  };

  # GitHub CLI. gitCredentialHelper (default on) wires HTTPS push/pull to
  # `gh auth git-credential` so we never need to write ~/.config/git/config
  # (that path is a Home Manager → Nix store symlink on this host).
  programs.gh = {
    enable = true;
    settings.git_protocol = "https";
  };

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

  # Default terminal across Plasma / GNOME / Xfce / Sway / Hyprland.
  programs.ghostty = {
    enable = true;
    settings = {
      font-family = "JetBrainsMono Nerd Font";
      font-size = 12;
      gtk-single-instance = true;
    };
  };

  home.sessionVariables.TERMINAL = "ghostty";

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

  home.packages = with pkgs; [
    btop
    # Cat clone with syntax highlighting (`bat`; Debian package name is batcat).
    bat
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
    # Pin 1.8.4 (nixpkgs currently ships 1.8.5). Same upstream zip layout.
    (jquake.overrideAttrs (_old: {
      version = "1.8.4";
      src = fetchurl {
        url = "https://github.com/fleneindre/fleneindre.github.io/raw/master/downloads/JQuake_1.8.4_linux.zip";
        hash = "sha256-oIYkYmI8uG4zjnm1Jq1mzIcSwRlKbWJqvACygQyp9sA=";
      };
    }))
    onlyoffice-desktopeditors
    # Raster editor (native).
    gimp
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
    # On-screen keystroke overlay (useful for demos / Chromebook Fn keys).
    showmethekey
    # Google Quick Share / Nearby Share client for Linux.
    rquickshare
    discord
    # Send Anywhere (upstream Electron .deb; not in nixpkgs).
    sendanywhere
  ];
}
