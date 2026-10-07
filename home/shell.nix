# Bash aliases and helpers shared across all greetd sessions.
{
  config,
  pkgs,
  ...
}:

let
  # Absolute flake path so `rebuild` works from $HOME (or any cwd), not only
  # when the shell is already inside the MySettings checkout.
  flakeUri = "${config.home.homeDirectory}/MySettings#mitac";
  nomBin = "${pkgs.nix-output-monitor}/bin/nom";
in
{
  programs.bash = {
    enable = true;
    # -1 = unlimited (bash: non-negative caps; negative / unset = no limit).
    historySize = -1;
    historyFileSize = -1;
    shellAliases = {
      ll = "ls -la";
      bcat = "bat";
      generations = "nixos-rebuild list-generations";
      # UniClipboard / ChatGPT .deb + nix flake update (Cursor / Send Anywhere / …).
      flake-update = "${config.home.homeDirectory}/MySettings/scripts/flake-update.sh";
      # Emergency: stop looping SOF amp playback (Broken pipe / stuck buffer).
      # Mute levels via the shared chromebook-speaker-levels helper (systemPackages).
      audio-panic = "chromebook-speaker-levels mute && systemctl --user restart pulseaudio.service 2>/dev/null; systemctl --user restart pipewire.service wireplumber.service 2>/dev/null; true";
      # When no display is up, gui wraps with cage; otherwise passthrough.
      vivaldi = "gui vivaldi";
      cursor = "gui cursor";
      code-cursor = "gui cursor";
      # Official Cursor Agent CLI name (`cursor-cli` ships cursor-agent only).
      agent = "cursor-agent";
      chatgpt = "gui chatgpt";
      deepseek-harness = "gui deepseek-harness";
      librechat = "gui librechat";
      onlyoffice-desktopeditors = "gui onlyoffice-desktopeditors";
      jquake = "gui jquake";
      parsec = "gui parsecd";
      bottles = "gui bottles";
      trayscale = "gui trayscale";
    };
    # Top ~10 lines: command output; bottom: btop. Usage: runbtop <cmd> [args...]
    # rebuild: same TTY as plain nixos-rebuild, with nom ETA alongside progress.
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

      rebuild() {
        sudo nixos-rebuild switch --flake ${flakeUri} --log-format internal-json -v |& ${nomBin} --json
        return "''${PIPESTATUS[0]}"
      }
    '';
  };
}
