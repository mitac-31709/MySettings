# Bash aliases and helpers shared across all greetd sessions.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # One option (default lib/machine.nix + flakeTarget). Works from any cwd,
  # not only inside the checkout. The flake-update* commands are store paths.
  repoPath = config.mitac.repoPath;
  defaultHost = config.mitac.flakeHost;
  hiraginoDir = (import ../lib/machine.nix).hiraginoDir;
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
      # .deb URLs + nix flake update of every input except nixpkgs-cursor.
      flake-update = lib.getExe config.mitac.scripts.flakeUpdate;
      # nixpkgs-cursor only (code-cursor / cursor-cli), same rev as nixpkgs otherwise.
      flake-update-cursor = lib.getExe config.mitac.scripts.flakeUpdateCursor;
      # Waybar upd indicator: compare pinned debs + GitHub flake tips (no mutate).
      flake-update-check = lib.getExe config.mitac.scripts.flakeUpdateCheck;
      # Emergency: mute speakers/sink and restart audio stack (PulseAudio on Chromebook, PipeWire on VAIO).
      audio-panic = "if command -v chromebook-speaker-levels >/dev/null 2>&1; then chromebook-speaker-levels mute || true; else ${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ 1 2>/dev/null || true; fi; for u in pulseaudio.service pipewire.service pipewire-pulse.service wireplumber.service; do systemctl --user restart $u 2>/dev/null || true; done";
      # When no display is up, gui wraps with cage; otherwise passthrough.
      vivaldi = "gui vivaldi";
      cursor = "gui cursor";
      code-cursor = "gui cursor";
      # Official Cursor Agent CLI name (`cursor-cli` ships cursor-agent only).
      agent = "cursor-agent";
      chatgpt = "gui chatgpt";
      grok-bot = "gui grok-bot";
      onlyoffice-desktopeditors = "gui onlyoffice-desktopeditors";
      jquake = "gui JQuake";
      parsec = "gui parsecd";
      bottles = "gui bottles";
      trayscale = "gui trayscale";
    };
    # Top ~10 lines: command output; bottom: btop. Usage: runbtop <cmd> [args...]
    # rebuild: sudo on this TTY first; then human-readable logs + nom ETA while building.
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
        local defaultTarget=${lib.escapeShellArg defaultHost}
        local target="''${1:-$defaultTarget}"
        local flakeUri=${lib.escapeShellArg repoPath}"#$target"
        # Ask for the password on the real TTY (|& nom swallows/hides the prompt).
        sudo -v || return $?
        # Resolve nom at call time (PATH) so GC of an old store path cannot break
        # a long-lived shell that still has this function body.
        local nom
        nom="$(command -v nom)" || {
          printf 'rebuild: nom not on PATH (nix-output-monitor)\n' >&2
          return 127
        }
        # Human-readable mode: pass-through eval/activation; ETA only while building.
        # pathExists of the Hiragino directory is false in pure eval. Pass
        # --impure only when the OTFs are actually on disk.
        local -a rebuildArgs=(--flake "$flakeUri")
        if [ -d ${lib.escapeShellArg hiraginoDir} ]; then
          rebuildArgs+=(--impure)
        fi
        sudo nixos-rebuild switch "''${rebuildArgs[@]}" |& "$nom"
        return "''${PIPESTATUS[0]}"
      }

      # Low-priority nix eval (CPU + IO). Prefer narrow config.… paths over options.…
      nix-eval-low() {
        nice -n 19 ionice -c3 nix eval "$@"
      }

      # Accept home LAN routes via Tailscale only when away. On the same
      # 192.168.1.0/24, --accept-routes steers LAN through galleria and breaks Wi-Fi.
      ts-home-routes() {
        case "''${1:-}" in
          on)
            tailscale set --accept-routes=true || return $?
            printf 'accept-routes=on（外出先向け。帰宅後は ts-home-routes off）\n'
            ;;
          off)
            tailscale set --accept-routes=false || return $?
            printf 'accept-routes=off（自宅 LAN 直通）\n'
            ;;
          status|"")
            if tailscale debug prefs 2>/dev/null | grep -q '"RouteAll": true'; then
              printf 'accept-routes=on\n'
            else
              printf 'accept-routes=off\n'
            fi
            ;;
          *)
            printf 'usage: ts-home-routes on|off|status\n' >&2
            return 2
            ;;
        esac
      }

      # Launch Parsec after clearing WARP and checking Tailscale to the host.
      # Host (Windows) must set app_custom_address to its Tailscale IP — see README.
      parsec-ts() {
        local host="''${1:-galleria-mitac}"
        warp-cli --accept-tos disconnect >/dev/null 2>&1 || warp-cli disconnect >/dev/null 2>&1 || true
        printf 'Tailscale ping %s …\n' "$host"
        if ! tailscale ping -c 2 -timeout 5s "$host"; then
          printf '到達できません。ホストの電源・Tailscale・WOL を確認してください。\n' >&2
          return 1
        fi
        gui parsecd
      }
    '';
  };
}
