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
      generations = "nixos-rebuild list-generations";
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

  # Plasma settings that live in shared KConfig files (merge, don't replace).
  # - fixed font: system monospace (was org/gnome/desktop/interface)
  # - Ctrl+Alt+T → Konsole (was GNOME Console / kgx custom keybinding)
  home.activation.plasmaDesktopPrefs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    kwriteconfig6=${pkgs.kdePackages.kconfig}/bin/kwriteconfig6
    $kwriteconfig6 --file kdeglobals --group General --key fixed \
      "JetBrainsMono Nerd Font,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    $kwriteconfig6 --file kglobalshortcutsrc \
      --group services --group org.kde.konsole.desktop \
      --key _launch "Ctrl+Alt+T"
  '';

  home.packages = with pkgs; [
    btop
    firefox
    code-cursor
    jquake
    onlyoffice-desktopeditors
    parsec-bin
    tmux
    trayscale
    vivaldi
  ];
}
