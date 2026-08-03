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

  xdg.configFile."nvim".source = ./nvim;
  xdg.dataFile."nvim/lazy/lazy.nvim".source = "${pkgs.vimPlugins.lazy-nvim}";

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
    # Wineprefix manager for Windows apps/games (FHS-wrapped).
    (bottles.override { removeWarningPopup = true; })
    tmux
    trayscale
    vivaldi
  ];
}
