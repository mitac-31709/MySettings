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
  resticPasswordCommand = pkgs.writeShellScript "restic-home-password" ''
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
    exec ${lib.getExe pkgs.rbw} get ${bitwardenItem}
  '';

  # Non-secret: only tells restic to ask Bitwarden (via rbw) for the password.
  # Safe to keep in the Nix store — it contains no key material.
  resticEnvFile = pkgs.writeText "restic-home.env" ''
    RESTIC_PASSWORD_COMMAND=${resticPasswordCommand}
  '';

  # Desktop notifications via the logged-in user's session bus (Plasma).
  # Same replace-id so start / progress / finish collapse into one bubble.
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
    exec ${notifySend} \
      --app-name=Restic \
      --urgency="$urgency" \
      -h ${notifyHint} \
      "$title" "$body"
  '';

  # Companion unit: poll journal progress lines while the backup oneshot runs.
  # Declared separately because ExecStartPre children are killed when preStart ends.
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

    for _ in $(seq 1 60); do
      if systemctl is-active --quiet ${backupUnit} \
        || systemctl is-activating --quiet ${backupUnit}; then
        break
      fi
      sleep 0.5
    done

    ${resticNotify} low "バックアップ開始" "/home/${user} → Google Drive"

    last=""
    while systemctl is-active --quiet ${backupUnit} \
      || systemctl is-activating --quiet ${backupUnit}; do
      line="$(
        journalctl -u ${backupUnit} -n 30 -o cat --no-pager 2>/dev/null \
          | grep -E '%|[0-9]+ / [0-9]+' \
          | tail -n 1 \
          | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
          || true
      )"
      if [ -n "$line" ] && [ "$line" != "$last" ]; then
        ${resticNotify} low "バックアップ進行中" "$line" || true
        last="$line"
      fi
      sleep 15
    done
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
    # notifier reads those lines for desktop updates (~every 20s).
    progressFps = 0.05;

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
        ${resticNotify} normal "バックアップ完了" \
          "''${summary:-/home/${user} → Google Drive}"
      else
        ${resticNotify} critical "バックアップ失敗" \
          "結果: ''${SERVICE_RESULT:-unknown}（journalctl -u ${backupUnit}）"
      fi
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
