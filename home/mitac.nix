{ pkgs, lib, ... }:

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
    };
  };

  programs.git = {
    enable = true;
    # Update these to your own identity.
    settings.user = {
      name = "mitac";
      email = "mitac@example.com";
    };
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

  # Neovim config → ~/.config/nvim
  xdg.configFile."nvim".source = ./nvim;

  # Bundle lazy.nvim from nixpkgs (no git clone bootstrap).
  xdg.dataFile."nvim/lazy/lazy.nvim".source = "${pkgs.vimPlugins.lazy-nvim}";

  home.packages = with pkgs; [
    btop
    firefox
    gnome-tweaks
    code-cursor
    parsec-bin
    vivaldi
  ];

  # Terminal / monospace font for GNOME (nvim icons / Nerd Font glyphs).
  # Mozc must be listed in input-sources; installing ibus-mozc alone is not enough.
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      monospace-font-name = "JetBrainsMono Nerd Font 12";
    };
    "org/gnome/Console" = {
      use-system-font = false;
      custom-font = "JetBrainsMono Nerd Font 12";
    };
    # Traditional scrolling (finger up → content up), not "natural"/reverse.
    "org/gnome/desktop/peripherals/touchpad" = {
      natural-scroll = false;
    };
    "org/gnome/desktop/input-sources" = {
      sources = [
        (lib.hm.gvariant.mkTuple [
          "xkb"
          "jp"
        ])
        (lib.hm.gvariant.mkTuple [
          "ibus"
          "mozc-jp"
        ])
      ];
    };
    # Ctrl+Alt+T → GNOME Console
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "Console";
      command = "kgx";
      binding = "<Control><Alt>t";
    };
  };
}
