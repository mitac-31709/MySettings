# Encrypted backup of the user's home + selected system state to Google Drive.
#
# Pieces:
#   - restic  : encrypted, deduplicated, snapshot-based backup engine.
#   - rclone  : Google Drive backend (restic talks to the "gdrive" remote).
#   - rbw     : CLI Bitwarden client. The restic repository password (i.e. the
#               encryption key) is stored in Bitwarden and fetched at runtime via
#               `rbw get`, so no key material lives on disk or in the Nix store.
#
# Paths:
#   - /home/mitac (with excludes for regenerable bulky trees)
#   - Root-only system state staged into the unit RuntimeDirectory:
#       NetworkManager Wi-Fi profiles, Bluetooth pairings, Cloudflare WARP,
#       Tailscale node state.
#     (/etc/shadow and ~/MySettings are intentionally not backed up.)
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

  # Matches RuntimeDirectory from the nixpkgs restic module for this unit.
  stagingRoot = "/run/restic-backups-home/system";
  nmStagingDir = "${stagingRoot}/nm-connections";
  bluetoothStagingDir = "${stagingRoot}/bluetooth";
  warpStagingDir = "${stagingRoot}/cloudflare-warp";
  tailscaleStagingDir = "${stagingRoot}/tailscale";

  # Root-only sources → staged copies readable by the backup user.
  systemStagingSources = [
    {
      src = "/etc/NetworkManager/system-connections";
      dest = nmStagingDir;
    }
    {
      src = "/var/lib/bluetooth";
      dest = bluetoothStagingDir;
    }
    {
      src = "/var/lib/cloudflare-warp";
      dest = warpStagingDir;
    }
    {
      src = "/var/lib/tailscale";
      dest = tailscaleStagingDir;
    }
  ];

  # Run as root (systemd ExecStartPre=+...) so mode-600/700 trees are readable.
  stageSystemState = pkgs.writeShellScript "restic-home-stage-system" ''
    set -eu
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.findutils
      ]
    }:$PATH"
    rm -rf "${stagingRoot}"
    mkdir -p "${stagingRoot}"
    ${lib.concatMapStringsSep "\n" (s: ''
      mkdir -p "${s.dest}"
      if [ -d "${s.src}" ]; then
        # Store copy stays writable for chown; do not preserve root-only ownership.
        find "${s.src}" -mindepth 1 -maxdepth 1 -exec \
          cp -a --no-preserve=ownership {} "${s.dest}/" \;
        chown -R ${user}:users "${s.dest}"
        chmod -R u=rwX,go= "${s.dest}"
      fi
    '') systemStagingSources}
  '';

  clearSystemStaging = pkgs.writeShellScript "restic-home-clear-system" ''
    set -eu
    rm -rf "${stagingRoot}"
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

    ${resticPanel} set "バックアップ …" "/home/${user} + システム → Google Drive" running || true
    ${resticNotify} low "バックアップ開始" "/home/${user} + システム → Google Drive" || true

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

  # Interactive CLI with the same env as the systemd unit (repo, rclone, Bitwarden).
  # NixOS names its auto-wrapper `restic-<name>`; we disable that and ship `backup`.
  # Bare `backup` / `backup -h` prints wrapper usage (not raw restic help).
  resticBackupCmd = pkgs.writeShellScriptBin "backup" ''
    if [ "$#" -eq 0 ] || [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
      cat <<'EOF'
backup — restic wrapper (repo / rclone / Bitwarden 鍵込み)

Usage:
  backup <restic-command> [args…]
  backup -h | --help

Common:
  backup snapshots
  backup restore latest --target /tmp/restore
  backup ls latest
  backup find NAME
  backup unlock

Full backup (systemd unit, not this CLI):
  sudo systemctl start restic-backups-home.service
  journalctl -u restic-backups-home -f

First-time setup:
  restic-home-setup

Notes:
  - restore は必ず --target を付ける（省略すると /home/mitac を上書き）
  - 鍵が必要なら先に rbw unlock
  - restic 本体のヘルプ: backup <command> --help
EOF
      exit 0
    fi

    set -a
    # shellcheck disable=SC1091
    source ${resticEnvFile}
    export RESTIC_CACHE_DIR="/var/cache/restic-backups-home"
    export RESTIC_REPOSITORY="${repository}"
    export RCLONE_CONFIG="${rcloneConfigFile}"
    export RESTIC_PROGRESS_FPS="0.2"
    PATH="${
      lib.makeBinPath [
        pkgs.rbw
        pkgs.rclone
        pkgs.openssh
      ]
    }:$PATH"
    exec ${lib.getExe pkgs.restic} "$@"
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

      # setuid sudo + system wrappers (backup) live outside the app PATH.
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

      # Google OAuth apps left in "Testing" issue refresh tokens that die ~weekly
      # (invalid_grant). Publishing (unverified is fine for personal use) fixes it.
      warn_oauth_publish() {
        say "CRITICAL: Google Cloud OAuth consent must be Published (not Testing)."
        say "  Testing mode → refresh tokens expire about every 7 days → invalid_grant."
        say "  Console: https://console.cloud.google.com/auth/audience"
        say "  Branding (owned domain; github.io is often rejected):"
        say "    app name: restic Home Backup"
        say "    home:     https://restic-oauth.mitac.f5.si/"
        say "    privacy:  https://restic-oauth.mitac.f5.si/privacy.html"
        say "    domain:   mitac.f5.si (Search Console Domain verify)"
        say "  Save Branding, then Audience → Publish app."
        say "  After publishing, reconnect so you get a long-lived refresh token."
        say "  Docs: https://rclone.org/drive/#making-your-own-client-id"
      }

      probe_gdrive() {
        # 0 = OK, 1 = auth/token failure, 2 = other failure
        # (command substitution alone would mask rclone's exit status)
        local err rc=0
        err="$(rclone about "''${remote_name}:" 2>&1)" || rc=$?
        if [ "$rc" -eq 0 ]; then
          return 0
        fi
        printf '%s\n' "$err" >&2
        case "$err" in
          *invalid_grant*|*token\ expired*|*couldn?t\ fetch\ token*) return 1 ;;
          *) return 2 ;;
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
        probe_rc=0
        probe_gdrive || probe_rc=$?
        if [ "$probe_rc" -eq 0 ]; then
          say "Google Drive auth OK (rclone about ''${remote_name}:)."
          if confirm "Reconfigure OAuth anyway (own client_id / refresh token)?"; then
            warn_oauth_publish
            say "Prefer your own Desktop OAuth client_id (shared rclone ID is rate-limited / retiring 2026)."
            rclone config reconnect "''${remote_name}:" || rclone config
          fi
        else
          say "Google Drive auth FAILED (probe exit $probe_rc)."
          warn_oauth_publish
          if ! confirm "Confirm the OAuth app is Published, then reconnect now?"; then
            die "Aborted. Publish the app, then: rclone config reconnect ''${remote_name}:"
          fi
          rclone config reconnect "''${remote_name}:" || rclone config
          probe_gdrive || die "Still cannot reach ''${remote_name}: after reconnect. Check Publish + client_id."
          say "Google Drive auth OK after reconnect."
        fi
      else
        say "Remote ''${remote_name}: missing. Launching interactive rclone config."
        warn_oauth_publish
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
        probe_gdrive || die "Remote ''${remote_name}: configured but auth probe failed."
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
      if command -v backup >/dev/null 2>&1; then
        if backup snapshots >/dev/null 2>&1; then
          say "backup can open the repository (existing snapshots OK)."
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
      say "  backup snapshots"
      say "  backup restore latest --target /tmp/restore"
    '';
  };
in
{
  environment.systemPackages = with pkgs; [
    restic
    rclone
    rbw
    resticBackupCmd
    resticHomeSetup
  ];

  services.restic.backups.home = {
    inherit user repository rcloneConfigFile;

    # Prefer a short `backup` CLI over nixpkgs' default `restic-home` wrapper.
    createWrapper = false;

    # Home plus staged root-only system state (Wi-Fi, Bluetooth, WARP, Tailscale).
    # On this single-user host /home/${user} is effectively all of /home.
    paths = [
      "/home/${user}"
      stagingRoot
    ];

    # Skip regenerable bulk (Steam client/runtime, Cursor agent binaries, browser
    # caches/extensions, Firefox storage), HM/Nix links, and MySettings (git).
    # Login password (/etc/shadow) is intentionally not staged.
    exclude = [
      "/home/${user}/.cache"
      "/home/${user}/.local/share/Trash"
      "/home/${user}/.config/mozilla/firefox/*/storage"
      "/home/${user}/.mozilla/firefox/*/storage"
      "/home/${user}/**/node_modules"
      "/home/${user}/**/.direnv"
      "/home/${user}/**/target"
      "/home/${user}/.local/state/nvim/swap"

      # Steam: game installs + client/runtime (re-downloadable). Keep config
      # (minus htmlcache), userdata, and Proton compatdata.
      "/home/${user}/.local/share/Steam/steamapps/common"
      "/home/${user}/.local/share/Steam/steamapps/downloading"
      "/home/${user}/.local/share/Steam/steamapps/temp"
      "/home/${user}/.local/share/Steam/steamapps/shadercache"
      "/home/${user}/.local/share/Steam/steamapps/workshop"
      "/home/${user}/.local/share/Steam/depotcache"
      "/home/${user}/.local/share/Steam/steamrt64"
      "/home/${user}/.local/share/Steam/steamrt32"
      "/home/${user}/.local/share/Steam/ubuntu12_32"
      "/home/${user}/.local/share/Steam/ubuntu12_64"
      "/home/${user}/.local/share/Steam/package"
      "/home/${user}/.local/share/Steam/steamui"
      "/home/${user}/.local/share/Steam/appcache"
      "/home/${user}/.local/share/Steam/linux32"
      "/home/${user}/.local/share/Steam/linux64"
      "/home/${user}/.local/share/Steam/legacycompat"
      "/home/${user}/.local/share/Steam/clientui"
      "/home/${user}/.local/share/Steam/bin"
      "/home/${user}/.local/share/Steam/graphics"
      "/home/${user}/.local/share/Steam/config/htmlcache"

      # Cursor: agent worker binaries + editor caches/logs.
      "/home/${user}/.config/Cursor/User/globalStorage/anysphere.cursor-agent-worker"
      "/home/${user}/.config/Cursor/CachedData"
      "/home/${user}/.config/Cursor/CachedProfilesData"
      "/home/${user}/.config/Cursor/Cache"
      "/home/${user}/.config/Cursor/Code Cache"
      "/home/${user}/.config/Cursor/GPUCache"
      "/home/${user}/.config/Cursor/DawnWebGPUCache"
      "/home/${user}/.config/Cursor/DawnGraphiteCache"
      "/home/${user}/.config/Cursor/IndexedDB"
      "/home/${user}/.config/Cursor/logs"

      # Vivaldi: regenerable caches, DRM/components, extensions, site WebStorage.
      "/home/${user}/.config/vivaldi/Default/Service Worker"
      "/home/${user}/.config/vivaldi/Default/GPUCache"
      "/home/${user}/.config/vivaldi/Default/Code Cache"
      "/home/${user}/.config/vivaldi/Default/Cache"
      "/home/${user}/.config/vivaldi/Default/Extensions"
      "/home/${user}/.config/vivaldi/Default/WebStorage"
      "/home/${user}/.config/vivaldi/component_crx_cache"
      "/home/${user}/.config/vivaldi/WasmTtsEngine"
      "/home/${user}/.config/vivaldi/WidevineCdm"
      "/home/${user}/.config/vivaldi/Safe Browsing"
      "/home/${user}/.config/vivaldi/GPUPersistentCache"
      "/home/${user}/.config/vivaldi/GraphiteDawnCache"

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
          "''${summary:-/home/${user} + システム → Google Drive}" done || true
        ${resticNotify} normal "バックアップ完了" \
          "''${summary:-/home/${user} + システム → Google Drive}" || true
      else
        fail_hint="結果: ''${SERVICE_RESULT:-unknown}（journalctl -u ${backupUnit}）"
        if journalctl -u ${backupUnit} -n 40 -o cat --no-pager 2>/dev/null \
          | grep -Eqi 'invalid_grant|token expired|couldn.t fetch token'; then
          fail_hint="GDrive OAuth失効。ConsoleでPublish後: rclone config reconnect gdrive:"
        elif journalctl -u ${backupUnit} -n 40 -o cat --no-pager 2>/dev/null \
          | grep -Eqi 'pinentry cancelled|Resolving password failed'; then
          fail_hint="rbw がロック。先に: rbw unlock"
        fi
        ${resticPanel} set "バックアップ失敗" "$fail_hint" failed || true
        ${resticNotify} critical "バックアップ失敗" "$fail_hint" || true
      fi
      # Leave the final panel label briefly; progress unit EXIT trap also clears.
      sleep 8
      ${resticPanel} clear || true
    '';

    # CLI: `backup` (see resticBackupCmd) — same env as this unit, e.g.:
    #   restic-home-setup
    #   backup snapshots
    #   backup restore latest --target /tmp/restore
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
    # "+" = run as root even though the unit User= is mitac (system trees are 0600/0700).
    serviceConfig = {
      ExecStartPre = [ "+${stageSystemState}" ];
      ExecStopPost = [ "+${clearSystemStaging}" ];
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
