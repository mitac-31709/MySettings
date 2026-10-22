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
      # UniClipboard / ChatGPT .deb + nix flake update (Cursor / …).
      flake-update = "${config.home.homeDirectory}/MySettings/scripts/flake-update.sh";
      # Waybar upd indicator: compare pinned debs + GitHub flake tips (no mutate).
      flake-update-check = "${config.home.homeDirectory}/MySettings/scripts/flake-update-check.sh";
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
        # Ask for the password on the real TTY (|& nom swallows/hides the prompt).
        sudo -v || return $?
        # Human-readable mode: pass-through eval/activation; ETA only while building.
        sudo nixos-rebuild switch --flake ${flakeUri} |& ${nomBin}
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
