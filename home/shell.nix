# Bash aliases and helpers shared across all greetd sessions.
{
  config,
  ...
}:

let
  # Absolute flake path so `rebuild` works from $HOME (or any cwd), not only
  # when the shell is already inside the MySettings checkout.
  flakeUri = "${config.home.homeDirectory}/MySettings#mitac";
in
{
  programs.bash = {
    enable = true;
    # -1 = unlimited (bash: non-negative caps; negative / unset = no limit).
    historySize = -1;
    historyFileSize = -1;
    shellAliases = {
      ll = "ls -la";
      rebuild = "sudo nixos-rebuild switch --flake ${flakeUri}";
      generations = "nixos-rebuild list-generations";
      # Emergency: stop looping SOF amp playback (Broken pipe / stuck buffer).
      # Mute levels via the shared chromebook-speaker-levels helper (systemPackages).
      audio-panic = "chromebook-speaker-levels mute && systemctl --user restart pulseaudio.service 2>/dev/null; systemctl --user restart pipewire.service wireplumber.service 2>/dev/null; true";
      # When no display is up, gui wraps with cage; otherwise passthrough.
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
}
