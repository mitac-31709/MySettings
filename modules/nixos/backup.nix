# Encrypted backup of the user's home to Google Drive.
#
# Pieces:
#   - restic  : encrypted, deduplicated, snapshot-based backup engine.
#   - rclone  : Google Drive backend (restic talks to the "gdrive" remote).
#   - rbw     : CLI Bitwarden client. The restic repository password (i.e. the
#               encryption key) is stored in Bitwarden and fetched at runtime via
#               `rbw get`, so no key material lives on disk or in the Nix store.
#
# What is declarative (this file) vs. manual (secrets, kept out of the store):
#   declarative : which paths, excludes, schedule, retention, the Google Drive
#                 target, and that the key comes from Bitwarden.
#   manual      : the rclone OAuth token for Google Drive and the Bitwarden login.
# See README.md → "Encrypted /home backup" for the one-time setup.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  user = "mitac";
  backupUnit = "restic-backups-home.service";

  # Google Drive destination: rclone remote "gdrive" plus a subpath. The remote
  # is configured out-of-band with `rclone config` (interactive OAuth).
  repository = "rclone:gdrive:restic/mitac-home";

  # rclone config holding the Google Drive OAuth token. Kept outside the Nix
  # store, readable by the backup user. Created with `rclone config`.
  rcloneConfigFile = "/home/${user}/.config/rclone/rclone.conf";

  # Bitwarden item whose password field holds the restic encryption key.
  bitwardenItem = "restic-home";

  # Wrapper so systemd's minimal PATH still finds rbw-agent. Always talk to
  # mitac's session agent (do not trust %U / id -u here: ExecStartPre can see
  # uid 0 and systemd %U has been observed to expand to 0 on this unit).
  # When the vault is locked, pinentry-qt needs the graphical session (D-Bus +
  # Wayland/X11); a bare systemd unit has neither unless we import them here.
  resticPasswordCommand = pkgs.writeShellScript "restic-home-password" ''
    set -eu
    export PATH="${
      lib.makeBinPath [
        pkgs.rbw
        pkgs.coreutils
        pkgs.getent
      ]
    }:$PATH"
    uid="$(getent passwd ${user} | cut -d: -f3)"
    export XDG_RUNTIME_DIR="/run/user/''${uid}"
    export HOME="/home/${user}"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/''${uid}/bus"

    if [ ! -S "/run/user/''${uid}/bus" ]; then
      echo "restic-home-password: ''${user} session bus missing (log in graphically, then: rbw unlock)" >&2
      exit 1
    fi

    # Import display so pinentry-qt can prompt if the vault is locked.
    if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
      for sock in /run/user/"''${uid}"/wayland-*; do
        case "$sock" in
          *.lock) continue ;;
        esac
        if [ -S "$sock" ]; then
          export WAYLAND_DISPLAY="$(basename "$sock")"
          break
        fi
      done
    fi
    if [ -z "''${DISPLAY:-}" ] && [ -e /tmp/.X11-unix/X0 ]; then
      export DISPLAY=:0
    fi
    if [ -z "''${XAUTHORITY:-}" ] && [ -f "/home/${user}/.Xauthority" ]; then
      export XAUTHORITY="/home/${user}/.Xauthority"
    fi

    exec ${lib.getExe pkgs.rbw} get ${bitwardenItem}
  '';

  # Non-secret: only tells restic to ask Bitwarden (via rbw) for the password.
  # Safe to keep in the Nix store — it contains no key material.
  resticEnvFile = pkgs.writeText "restic-home.env" ''
    RESTIC_PASSWORD_COMMAND=${resticPasswordCommand}
  '';

  # Desktop notifications via the logged-in user's session bus.
  # Same replace-id so start / finish collapse into one bubble.
  # Mid-run progress is shown on the Sway waybar panel (status file below).
  notifySend = lib.getExe pkgs.libnotify;
  notifyHint = "string:x-canonical-private-synchronous:restic-home";

  resticNotify = pkgs.writeShellScript "restic-home-notify" ''
    set -eu
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.getent
      ]
    }:$PATH"
    uid="$(getent passwd ${user} | cut -d: -f3)"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/''${uid}/bus"
    export XDG_RUNTIME_DIR="/run/user/''${uid}"
    urgency="$1"
    title="$2"
    body="$3"
    # Session bus may be absent (no graphical login); do not fail the backup.
    if [ ! -S "/run/user/''${uid}/bus" ]; then
      echo "restic-home-notify: no session bus for ''${user}; skip: $title" >&2
      exit 0
    fi
    exec ${notifySend} \
      --app-name=Restic \
      --urgency="$urgency" \
      -h ${notifyHint} \
      "$title" "$body"
  '';

  # Write / clear the waybar status JSON under mitac's XDG_RUNTIME_DIR.
  resticPanel = pkgs.writeShellScript "restic-home-panel" ''
    set -eu
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.getent
        pkgs.jq
        pkgs.procps
        pkgs.util-linux
      ]
    }:$PATH"
    uid="$(getent passwd ${user} | cut -d: -f3)"
    status="/run/user/''${uid}/restic-home-status"
    action="$1"

    signal_waybar() {
      runuser -u ${user} -- env XDG_RUNTIME_DIR="/run/user/''${uid}" \
        pkill -SIGRTMIN+8 -x waybar >/dev/null 2>&1 || true
    }

    case "$action" in
      clear)
        rm -f "$status"
        signal_waybar
        ;;
      set)
        text="$2"
        tooltip="''${3:-$text}"
        class="''${4:-running}"
        jq -nc \
          --arg text "$text" \
          --arg tooltip "$tooltip" \
          --arg class "$class" \
          '{text:$text, tooltip:$tooltip, class:$class}' >"$status"
        chown ${user}:users "$status" 2>/dev/null || chown ${user} "$status" || true
        chmod 644 "$status" || true
        signal_waybar
        ;;
      *)
        echo "usage: restic-home-panel set <text> [tooltip] [class] | clear" >&2
        exit 2
        ;;
    esac
  '';

  # Companion unit: poll journal progress lines while the backup oneshot runs.
  # Declared separately because ExecStartPre children are killed when preStart ends.
  # Note: `systemctl is-activating` is not a real verb; use ActiveState instead.
  progressNotifyScript = pkgs.writeShellScript "restic-home-progress-notify" ''
    set -eu
    export PATH="${
      lib.makeBinPath [
        pkgs.systemd
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
      ]
    }:$PATH"

    unit_busy() {
      case "$(systemctl show -p ActiveState --value ${backupUnit} 2>/dev/null || true)" in
        active|activating) return 0 ;;
        *) return 1 ;;
      esac
    }

    for _ in $(seq 1 60); do
      if unit_busy; then
        break
      fi
      sleep 0.5
    done

    if ! unit_busy; then
      # Backup never reached activating/active (e.g. pre-start failed fast).
      exit 0
    fi

    ${resticPanel} set "バックアップ …" "/home/${user} → Google Drive" running || true
    ${resticNotify} low "バックアップ開始" "/home/${user} → Google Drive" || true

    last=""
    while unit_busy; do
      line="$(
        journalctl -u ${backupUnit} -n 30 -o cat --no-pager 2>/dev/null \
          | grep -E '%|[0-9]+ / [0-9]+' \
          | tail -n 1 \
          | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
          || true
      )"
      if [ -n "$line" ] && [ "$line" != "$last" ]; then
        pct="$(printf '%s\n' "$line" | sed -n 's/.*[^0-9]\([0-9]\{1,3\}\)\.[0-9]\+%.*$/\1/p')"
        if [ -z "$pct" ]; then
          pct="$(printf '%s\n' "$line" | sed -n 's/.*[^0-9]\([0-9]\{1,3\}\)%.*$/\1/p')"
        fi
        if [ -n "$pct" ]; then
          text="バックアップ ''${pct}%"
        else
          text="バックアップ中"
        fi
        ${resticPanel} set "$text" "$line" running || true
        last="$line"
      fi
      sleep 2
    done

    # Final label + clear are handled by backupCleanupCommand (avoids racing partOf stop).
  '';
in
{
  environment.systemPackages = with pkgs; [
    restic
    rclone
    rbw
  ];

  services.restic.backups.home = {
    inherit user repository rcloneConfigFile;

    # The user's data under /home. On this single-user host this is effectively
    # all of /home. To back up every user's home, run as root instead and point
    # rclone/rbw at root's config.
    paths = [ "/home/${user}" ];

    # Skip caches, trash and large regenerable build artifacts.
    exclude = [
      "/home/${user}/.cache"
      "/home/${user}/.local/share/Trash"
      "/home/${user}/.mozilla/firefox/*/storage"
      "/home/${user}/**/node_modules"
      "/home/${user}/**/.direnv"
      "/home/${user}/**/target"
      "/home/${user}/.local/state/nvim/swap"
    ];

    # Provides RESTIC_PASSWORD_COMMAND → key stays in Bitwarden.
    environmentFile = "${resticEnvFile}";

    # Create the restic repository on Google Drive on first run.
    initialize = true;

    # Emit progress to the journal even under systemd (non-TTY); companion
    # notifier / waybar panel reads those lines (~every few seconds).
    progressFps = 0.2;

    # Retention: prune old snapshots after each run.
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
    ];

    # Run daily; catch up if the machine was powered off at the scheduled time.
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };

    # Final status (postStop always runs; SERVICE_RESULT distinguishes success).
    backupCleanupCommand = ''
      summary="$(
        journalctl -u ${backupUnit} -n 80 -o cat --no-pager 2>/dev/null \
          | grep -E 'Files:|Dirs:|Added to the repository|processed [0-9]' \
          | tail -n 4 \
          | tr '\n' ' ' \
          | sed -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//' \
          || true
      )"
      if [ "''${SERVICE_RESULT:-}" = success ]; then
        ${resticPanel} set "バックアップ完了" \
          "''${summary:-/home/${user} → Google Drive}" done || true
        ${resticNotify} normal "バックアップ完了" \
          "''${summary:-/home/${user} → Google Drive}" || true
      else
        ${resticPanel} set "バックアップ失敗" \
          "結果: ''${SERVICE_RESULT:-unknown}" failed || true
        ${resticNotify} critical "バックアップ失敗" \
          "結果: ''${SERVICE_RESULT:-unknown}（journalctl -u ${backupUnit}）" || true
      fi
      # Leave the final panel label briefly; progress unit EXIT trap also clears.
      sleep 8
      ${resticPanel} clear || true
    '';

    # createWrapper defaults to true → installs a `restic-home` command with the
    # same environment (repository, rclone config, Bitwarden password command) so
    # you can list snapshots or restore without re-specifying anything, e.g.:
    #   restic-home snapshots
    #   restic-home restore latest --target /tmp/restore
  };

  # Systemd's default PATH for this unit does not include profile bins; restic
  # needs rclone on PATH, and rbw needs rbw-agent. Start the progress notifier
  # alongside this oneshot (partOf stops it when the backup ends).
  systemd.services.restic-backups-home = {
    path = [
      pkgs.rbw
      pkgs.rclone
      pkgs.openssh
      pkgs.systemd
      pkgs.gnugrep
      pkgs.gnused
      pkgs.coreutils
    ];
    wants = [ "restic-backups-home-progress.service" ];
    after = [ "restic-backups-home-progress.service" ];
  };

  # Runs as root so journalctl can read the system unit; notify-send still
  # targets mitac's session bus (see resticNotify).
  systemd.services.restic-backups-home-progress = {
    description = "Desktop progress notifications for restic home backup";
    partOf = [ backupUnit ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${progressNotifyScript}";
    };
  };
}
