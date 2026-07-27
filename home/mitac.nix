{ pkgs, ... }:

{
  home.username = "mitac";
  home.homeDirectory = "/home/mitac";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "ls -la";
      rebuild = "sudo nixos-rebuild switch --flake .#mitac";
      generations = "nixos-rebuild list-generations";
    };
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
  xdg.configFile."kcminputrc".text = ''
    [Keyboard]
    NumLock=0
  '';

  # Neovim config → ~/.config/nvim
  xdg.configFile."nvim".source = ./nvim;

  # Bundle lazy.nvim from nixpkgs (no git clone bootstrap).
  xdg.dataFile."nvim/lazy/lazy.nvim".source = "${pkgs.vimPlugins.lazy-nvim}";

  home.packages = with pkgs; [
    btop
    firefox
    code-cursor
    parsec-bin
    vivaldi
  ];
}
