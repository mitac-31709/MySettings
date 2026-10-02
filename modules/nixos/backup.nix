# Encrypted backup of the user's home (+ Wi-Fi) to Google Drive.
#
# Pieces:
#   - restic  : encrypted, deduplicated, snapshot-based backup engine.
#   - rclone  : Google Drive backend (restic talks to the "gdrive" remote).
#   - rbw     : CLI Bitwarden client. The restic repository password (i.e. the
#               encryption key) is stored in Bitwarden and fetched at runtime via
#               `rbw get`, so no key material lives on disk or in the Nix store.
#
# Paths:
#   - /home/mitac
#   - NetworkManager system connections (Wi-Fi SSIDs/PSKs). Those files are
#     root:root mode 600 under /etc/NetworkManager/system-connections; the
#     backup user cannot read them, so a root ExecStartPre stages a copy into
#     the unit RuntimeDirectory for the duration of the run.
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

  # NetworkManager Wi-Fi profiles (SSIDs + PSKs). Staged for the backup user.
  nmConnectionsDir = "/etc/NetworkManager/system-connections";
  # Matches RuntimeDirectory from the nixpkgs restic module for this unit.
  nmStagingDir = "/run/restic-backups-home/nm-connections";

  # Run as root (systemd ExecStartPre=+...) so mode-600 NM files are readable.
  stageNmConnections = pkgs.writeShellScript "restic-home-stage-nm" ''
    set -eu
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.findutils
      ]
    }:$PATH"
    rm -rf "${nmStagingDir}"
    mkdir -p "${nmStagingDir}"
    if [ -d "${nmConnectionsDir}" ]; then
      # Store copy stays writable for chown; do not preserve root-only ownership.
      find "${nmConnectionsDir}" -mindepth 1 -maxdepth 1 -exec \
        cp -a --no-preserve=ownership {} "${nmStagingDir}/" \;
      chown -R ${user}:users "${nmStagingDir}"
      chmod -R u=rwX,go= "${nmStagingDir}"
    fi
  '';

  clearNmStaging = pkgs.writeShellScript "restic-home-clear-nm" ''
    set -eu
    rm -rf "${nmStagingDir}"
  '';

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

    ${resticPanel} set "バックアップ …" "/home/${user} + Wi-Fi → Google Drive" running || true
    ${resticNotify} low "バックアップ開始" "/home/${user} + Wi-Fi → Google Drive" || true

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

  # Interactive first-time setup: rclone gdrive remote, Bitwarden key, first backup.
  # Secrets stay out of the Nix store (OAuth token + restic key live in user config / BW).
  resticHomeSetup = pkgs.writeShellApplication {
    name = "restic-home-setup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.rbw
      pkgs.rclone
      pkgs.restic
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      # setuid sudo + system wrappers (restic-home) live outside the app PATH.
      export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"

      remote_name="gdrive"
      rclone_conf="${rcloneConfigFile}"
      bw_item="${bitwardenItem}"
      repo="${repository}"
      unit="${backupUnit}"

      say() { printf '%s\n' "$*"; }
      step() { printf '\n==> %s\n' "$*"; }
      die() { printf 'error: %s\n' "$*" >&2; exit 1; }

      confirm() {
        local prompt="$1"
        local reply
        printf '%s [y/N] ' "$prompt"
        read -r reply || true
        case "$reply" in
          y|Y|yes|YES) return 0 ;;
          *) return 1 ;;
        esac
      }

      say "restic home backup — first-time setup"
      say "repo: $repo"
      say "rclone config: $rclone_conf"
      say "Bitwarden item: $bw_item"

      # --- 1. rclone Google Drive remote ---------------------------------
      step "1/3 Google Drive remote ($remote_name)"
      export RCLONE_CONFIG="$rclone_conf"
      mkdir -p "$(dirname "$rclone_conf")"

      has_remote=0
      if [ -f "$rclone_conf" ] && rclone listremotes 2>/dev/null | grep -qx "''${remote_name}:"; then
        has_remote=1
      fi

      if [ "$has_remote" -eq 1 ]; then
        say "Remote ''${remote_name}: already configured."
        if confirm "Reconfigure OAuth (own Google client_id / refresh token)?"; then
          say "Prefer your own Desktop OAuth client_id (shared rclone ID is rate-limited / retiring 2026)."
          say "Docs: https://rclone.org/drive/#making-your-own-client-id"
          rclone config
        fi
      else
        say "Remote ''${remote_name}: missing. Launching interactive rclone config."
        say "Create a remote named exactly ''${remote_name} (storage: Google Drive / drive)."
        say "IMPORTANT: paste your own Google Cloud OAuth client_id and client_secret"
        say "(Desktop app). Do not leave them blank — shared rclone client_id is slow and"
        say "being retired in 2026. See: https://rclone.org/drive/#making-your-own-client-id"
        say "Then complete browser OAuth and quit the rclone menu."
        if ! confirm "Start rclone config now?"; then
          die "Aborted. Re-run restic-home-setup after configuring rclone."
        fi
        rclone config
        if ! rclone listremotes 2>/dev/null | grep -qx "''${remote_name}:"; then
          die "Remote ''${remote_name}: still missing after rclone config."
        fi
        say "Remote ''${remote_name}: OK."
      fi

      # --- 2. Bitwarden (rbw) + restic encryption key --------------------
      step "2/3 Bitwarden key ($bw_item)"

      if ! rbw unlocked >/dev/null 2>&1; then
        say "Vault is locked (or not logged in)."
        if ! confirm "Run rbw login / unlock now?"; then
          die "Aborted. Run: rbw login && rbw unlock"
        fi
        # login is idempotent-ish; unlock prompts via pinentry when needed.
        rbw login || true
        rbw unlock
      else
        say "Vault is unlocked."
      fi

      rbw sync >/dev/null || true

      if rbw get "$bw_item" >/dev/null 2>&1; then
        say "Bitwarden item '$bw_item' already exists."
      else
        say "Creating Bitwarden item '$bw_item' (40-char generated passphrase = restic key)."
        if ! confirm "Generate and store a new restic key as '$bw_item'?"; then
          die "Aborted. Create the item manually: rbw generate 40 $bw_item"
        fi
        rbw generate 40 "$bw_item"
        rbw sync >/dev/null || true
        if ! rbw get "$bw_item" >/dev/null 2>&1; then
          die "Failed to read '$bw_item' after generate."
        fi
        say "Key stored in Bitwarden as '$bw_item'."
      fi

      # Smoke-check: restic can decrypt the password command path via wrapper.
      if command -v restic-home >/dev/null 2>&1; then
        if restic-home snapshots >/dev/null 2>&1; then
          say "restic-home can open the repository (existing snapshots OK)."
        else
          say "Repository not readable yet (expected before first backup / initialize)."
        fi
      fi

      # --- 3. First backup -----------------------------------------------
      step "3/3 First backup ($unit)"
      say "This creates the restic repo on Google Drive if needed (initialize = true)."
      if confirm "Start $unit now (may prompt for sudo)?"; then
        if systemctl --quiet is-active "$unit" 2>/dev/null; then
          say "$unit is already running."
        elif systemctl start "$unit" 2>/dev/null; then
          say "Started $unit."
        else
          sudo systemctl start "$unit"
          say "Started $unit (via sudo)."
        fi
        say "Follow logs with:"
        say "  journalctl -u $unit -f"
      else
        say "Skipped. Start later with:"
        say "  sudo systemctl start $unit"
        say "  journalctl -u $unit -f"
      fi

      say ""
      say "Done. Afterwards:"
      say "  restic-home snapshots"
      say "  restic-home restore latest --target /tmp/restore"
    '';
  };
in
{
  environment.systemPackages = with pkgs; [
    restic
    rclone
    rbw
    resticHomeSetup
  ];

  services.restic.backups.home = {
    inherit user repository rcloneConfigFile;

    # Home plus a staged copy of NetworkManager system connections (Wi-Fi).
    # On this single-user host /home/${user} is effectively all of /home.
    paths = [
      "/home/${user}"
      nmStagingDir
    ];

    # Skip caches, trash, regenerable HM/Nix links, Steam game installs
    # (re-downloadable; saves stay in userdata/compatdata), and the MySettings
    # flake checkout (tracked in git; restore copies are not wanted in the repo).
    exclude = [
      "/home/${user}/.cache"
      "/home/${user}/.local/share/Trash"
      "/home/${user}/.mozilla/firefox/*/storage"
      "/home/${user}/**/node_modules"
      "/home/${user}/**/.direnv"
      "/home/${user}/**/target"
      "/home/${user}/.local/state/nvim/swap"
      "/home/${user}/.local/share/Steam/steamapps/common"
      "/home/${user}/.local/share/Steam/steamapps/downloading"
      "/home/${user}/.local/share/Steam/steamapps/temp"
      "/home/${user}/.local/share/Steam/steamapps/shadercache"
      "/home/${user}/.local/share/Steam/steamapps/workshop"
      "/home/${user}/.local/share/Steam/depotcache"
      "/home/${user}/MySettings"
      "/home/${user}/.bash_history"
      "/home/${user}/.bash_profile"
      "/home/${user}/.bashrc"
      "/home/${user}/.nix-defexpr"
      "/home/${user}/.nix-profile"
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
          "''${summary:-/home/${user} + Wi-Fi → Google Drive}" done || true
        ${resticNotify} normal "バックアップ完了" \
          "''${summary:-/home/${user} + Wi-Fi → Google Drive}" || true
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
    #   restic-home-setup
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
    # "+" = run as root even though the unit User= is mitac (NM files are 0600).
    serviceConfig = {
      ExecStartPre = [ "+${stageNmConnections}" ];
      ExecStopPost = [ "+${clearNmStaging}" ];
    };
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
