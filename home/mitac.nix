{ pkgs, ... }:

{
  home.username = "mitac";
  home.homeDirectory = "/home/mitac";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "ls -la";
      rebuild = "sudo nixos-rebuild switch --flake .#mitac";
    };
  };

  programs.git = {
    enable = true;
    # Update these to your own identity.
    userName = "mitac";
    userEmail = "mitac@example.com";
  };

  # Bitwarden client (rbw). Holds the restic backup encryption key; see
  # modules/nixos/backup.nix. Log in once with `rbw login` after first switch.
  programs.rbw = {
    enable = true;
    settings = {
      # Update to your own Bitwarden account email.
      email = "mitac@example.com";
      # GNOME pinentry to prompt for the master password when unlocking.
      pinentry = pkgs.pinentry-gnome3;
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

  # Neovim config → ~/.config/nvim
  xdg.configFile."nvim".source = ./nvim;

  # Bundle lazy.nvim from nixpkgs (no git clone bootstrap).
  xdg.dataFile."nvim/lazy/lazy.nvim".source = "${pkgs.vimPlugins.lazy-nvim}";

  home.packages = with pkgs; [
    firefox
    gnome-tweaks
    code-cursor
    parsec-bin
  ];

  # Terminal / monospace font for GNOME (nvim icons / Nerd Font glyphs).
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      monospace-font-name = "JetBrainsMono Nerd Font 12";
    };
    "org/gnome/Console" = {
      use-system-font = false;
      custom-font = "JetBrainsMono Nerd Font 12";
    };
  };
}
