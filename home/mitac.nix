{
  pkgs,
  config,
  ...
}:

let
  # Absolute flake path so `rebuild` works from $HOME (or any cwd), not only
  # when the shell is already inside the MySettings checkout.
  flakeUri = "${config.home.homeDirectory}/MySettings#mitac";
in
{
  imports = [
    ./plasma.nix
    ./sessions/hyprland.nix
  ];

  home.username = "mitac";
  home.homeDirectory = "/home/mitac";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

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
      bottles = "gui bottles";
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
