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
    userName = "mitac";
    userEmail = "mitac@example.com";
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
  };
}
