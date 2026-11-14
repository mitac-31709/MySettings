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
#   - /home/mitac (with excludes for regenerable bulky trees; includes ~/MySettings)
#   - Root-only system state staged into the unit RuntimeDirectory:
#       NetworkManager Wi-Fi profiles, Bluetooth pairings, Cloudflare WARP,
#       Tailscale node state.
#     (/etc/shadow is intentionally not backed up.)
#
# What is declarative (this file) vs. manual (secrets, kept out of the store):
#   declarative : which paths, excludes, schedule, retention, the Google Drive
#                 target, and that the key comes from Bitwarden.
#   manual      : the rclone OAuth token for Google Drive and the Bitwarden login.
# See README.md → "/home の暗号化バックアップ" for the one-time setup.
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

  # Bitwarden item whose password field holds the restic encryption key
  # (client_id / client_secret / refresh_token can also be saved in its notes
  # or custom fields so scripts/restore-on-nixos.sh can load them via rbw).
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

  # Print client_id / client_secret / refresh_token from rclone config so the
  # user can paste or save them in Bitwarden item "restic-home" (notes or custom fields).
  printRcloneBitwardenFields = pkgs.writeShellScript "restic-home-show-oauth" ''
    set -eu
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.jq
        pkgs.rclone
      ]
    }:$PATH"
    remote="$1"
    bw_item="$2"
    dump_json="$(rclone config dump 2>/dev/null || true)"
    client_id=""
    client_secret=""
    refresh_token=""
    if [ -n "$dump_json" ]; then
      client_id="$(printf '%s\n' "$dump_json" | jq -r --arg r "$remote" '.[$r].client_id // empty' 2>/dev/null || true)"
      client_secret="$(printf '%s\n' "$dump_json" | jq -r --arg r "$remote" '.[$r].client_secret // empty' 2>/dev/null || true)"
      refresh_token="$(
        printf '%s\n' "$dump_json" | jq -r --arg r "$remote" '
          (try ((.[$r].token // "") | fromjson) catch null)
          | if type == "object" then (.refresh_token // empty) else empty end
        ' 2>/dev/null || true
      )"
    fi
    printf '\nBitwarden の項目「%s」に保存（メモ欄へ貼り付け、または同名カスタムフィールドを作成）:\n' "$bw_item"
    printf '  client_id: %s\n' "''${client_id:-(未設定)}"
    printf '  client_secret: %s\n' "''${client_secret:-(未設定)}"
    printf '  refresh_token: %s\n' "''${refresh_token:-(未設定)}"
    printf '  ※ 固定値（remote=%s, type=drive, scope=drive）の保存は不要です。\n' "$remote"
    printf '  ※ 復元時 ./scripts/restore-on-nixos.sh が rbw 経由で自動読込します。\n'
  '';

  # Single entrypoint for home backup ops (systemd / rclone / rbw / restic).
  # NixOS names its auto-wrapper `restic-<name>`; we disable that and ship `backup`.
  # Meta subcommands are handled here; everything else is passed to restic.
  resticBackupCmd = pkgs.writeShellScriptBin "backup" ''
    set -euo pipefail

    unit="${backupUnit}"
    timer="restic-backups-home.timer"
    remote_name="gdrive"
    rclone_conf="${rcloneConfigFile}"

    # setuid sudo + packaged CLIs (restic-home-setup lives on the system profile).
    PATH="${
      lib.makeBinPath [
        pkgs.rbw
        pkgs.rclone
        pkgs.jq
        pkgs.openssh
        pkgs.systemd
        pkgs.coreutils
      ]
    }:/run/wrappers/bin:/run/current-system/sw/bin:$PATH"

    usage() {
      cat <<'EOF'
backup — ホーム暗号化バックアップ CLI (restic / rclone / Bitwarden / systemd)

使い方:
  backup <command> [args…]
  backup -h | --help | help

基本ワークフロー:
  backup unlock-key              rbw unlock（Bitwarden から restic 鍵を解錠）
  backup setup                   対話式初回セットアップ (restic-home-setup)
  backup reconnect               rclone OAuth 再接続 (gdrive:)
  backup about                   Google Drive 疎通確認
  backup run                     フルバックアップ開始 (systemd)
  backup log                     進捗・ログを journal で追う
  backup status                  unit / timer の状態を表示

確認・部分復元（リポジトリ＆暗号化鍵の環境変数読み込み済み）:
  backup snapshots
  backup ls latest
  backup find NAME
  backup restore latest --target /tmp/restore
  backup unlock                  古い restic リポジトリロックを解除

注意:
  - restore には必ず --target を指定する（省略すると /home/mitac を上書き）
  - restic サブコマンドの詳細ヘルプ: backup <command> --help
  - 上記以外の第1引数はそのまま restic へ渡されます
EOF
    }

    cmd="''${1:-}"
    case "$cmd" in
      ""|-h|--help|help)
        usage
        exit 0
        ;;
      run|start)
        shift
        if systemctl --quiet is-active "$unit" 2>/dev/null; then
          printf '%s は既に実行中です。\n' "$unit"
        elif systemctl start "$unit" 2>/dev/null; then
          printf '%s を開始しました。\n' "$unit"
        else
          sudo systemctl start "$unit"
          printf '%s を開始しました（sudo 経由）。\n' "$unit"
        fi
        printf 'ログ確認: backup log\n'
        ;;
      log|logs)
        shift
        exec journalctl -u "$unit" -f "$@"
        ;;
      status)
        shift
        systemctl status "$unit" --no-pager "$@" || true
        printf '\n'
        systemctl status "$timer" --no-pager || true
        ;;
      setup)
        shift
        exec restic-home-setup "$@"
        ;;
      reconnect)
        shift
        export RCLONE_CONFIG="$rclone_conf"
        rclone config reconnect "''${remote_name}:" "$@"
        for arg in "$@"; do
          case "$arg" in
            -h|--help|--help=*) exit 0 ;;
          esac
        done
        ${printRcloneBitwardenFields} "$remote_name" "${bitwardenItem}"
        ;;
      about)
        shift
        export RCLONE_CONFIG="$rclone_conf"
        exec rclone about "''${remote_name}:" "$@"
        ;;
      unlock-key)
        shift
        exec rbw unlock "$@"
        ;;
      *)
        set -a
        # shellcheck disable=SC1091
        source ${resticEnvFile}
        export RESTIC_CACHE_DIR="/var/cache/restic-backups-home"
        export RESTIC_REPOSITORY="${repository}"
        export RCLONE_CONFIG="${rcloneConfigFile}"
        export RESTIC_PROGRESS_FPS="0.2"
        exec ${lib.getExe pkgs.restic} "$@"
        ;;
    esac
  '';

  # Interactive first-time setup: rclone gdrive remote, Bitwarden key, first backup.
  # Secrets stay out of the Nix store (OAuth token + restic key live in user config / BW).
  resticHomeSetup = pkgs.writeShellApplication {
    name = "restic-home-setup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
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
      die() { printf 'エラー: %s\n' "$*" >&2; exit 1; }

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
        say "重要: Google Cloud の OAuth 同意画面は「本番環境に公開 (Publish)」にしてください（Testing 不可）。"
        say "  Testing のままだと refresh_token が約 7 日で失効します（invalid_grant）。"
        say "  Console: https://console.cloud.google.com/auth/audience"
        say "  Branding（所有ドメイン必須。github.io は却下されやすい）:"
        say "    アプリ名: restic Home Backup"
        say "    ホームページ: https://restic-oauth.mitac.f5.si/"
        say "    プライバシー: https://restic-oauth.mitac.f5.si/privacy.html"
        say "    承認済みドメイン: mitac.f5.si（Search Console でドメイン確認済み）"
        say "  Branding 保存後、Audience → Publish app を押してください。"
        say "  Publish 後に再接続すると長寿命の refresh_token が発行されます。"
        say "  参考: https://rclone.org/drive/#making-your-own-client-id"
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

      say "restic ホームバックアップ — 初回セットアップ"
      say "リポジトリ: $repo"
      say "rclone 設定: $rclone_conf"
      say "Bitwarden 項目: $bw_item"

      # --- 1. rclone Google Drive remote ---------------------------------
      step "1/3 Google Drive リモート ($remote_name)"
      export RCLONE_CONFIG="$rclone_conf"
      mkdir -p "$(dirname "$rclone_conf")"

      has_remote=0
      if [ -f "$rclone_conf" ] && rclone listremotes 2>/dev/null | grep -qx "''${remote_name}:"; then
        has_remote=1
      fi

      if [ "$has_remote" -eq 1 ]; then
        say "リモート ''${remote_name}: は既に設定済みです。"
        probe_rc=0
        probe_gdrive || probe_rc=$?
        if [ "$probe_rc" -eq 0 ]; then
          say "Google Drive 認証 OK (rclone about ''${remote_name}:)。"
          if confirm "OAuth を再設定しますか（独自 client_id / refresh_token）？"; then
            warn_oauth_publish
            say "独自の Desktop OAuth client_id を設定してください（共有 ID は制限／2026 年廃止予定）。"
            rclone config reconnect "''${remote_name}:" || rclone config
          fi
        else
          say "Google Drive 認証エラー（終了コード $probe_rc）。"
          warn_oauth_publish
          if ! confirm "OAuth アプリを公開 (Publish) 済みであることを確認し、今すぐ再接続しますか？"; then
            die "中断しました。アプリを公開してから次を実行してください: rclone config reconnect ''${remote_name}:"
          fi
          rclone config reconnect "''${remote_name}:" || rclone config
          probe_gdrive || die "再接続後も ''${remote_name}: へ接続できませんでした。Publish と client_id を確認してください。"
          say "再接続後の Google Drive 認証 OK。"
        fi
      else
        say "リモート ''${remote_name}: が未設定です。対話式 rclone config を起動します。"
        warn_oauth_publish
        say "リモート名は必ず ''${remote_name}（storage: Google Drive / drive）にしてください。"
        say "重要: 自分で作成した Google Cloud の Desktop OAuth client_id と client_secret を"
        say "貼り付けてください（空欄にすると共有クライアントになり低速・廃止対象です）。"
        say "参考: https://rclone.org/drive/#making-your-own-client-id"
        say "ブラウザー OAuth を完了し、rclone メニューを終了 (q) してください。"
        if ! confirm "rclone config を開始しますか？"; then
          die "中断しました。rclone 設定後に次を再実行してください: backup setup"
        fi
        rclone config
        if ! rclone listremotes 2>/dev/null | grep -qx "''${remote_name}:"; then
          die "rclone config 完了後もリモート ''${remote_name}: が見つかりません。"
        fi
        probe_gdrive || die "リモート ''${remote_name}: を作成しましたが認証確認に失敗しました。"
        say "リモート ''${remote_name}: OK。"
      fi

      # --- 2. Bitwarden (rbw) + restic encryption key --------------------
      step "2/3 Bitwarden 暗号化鍵 ($bw_item)"

      if ! rbw unlocked >/dev/null 2>&1; then
        say "Bitwarden Vault がロック中（または未ログイン）です。"
        if ! confirm "今すぐ rbw login / unlock を実行しますか？"; then
          die "中断しました。次を実行してください: rbw login && rbw unlock"
        fi
        # login is idempotent-ish; unlock prompts via pinentry when needed.
        rbw login || true
        rbw unlock
      else
        say "Vault はロック解除済みです。"
      fi

      rbw sync >/dev/null || true

      if rbw get "$bw_item" >/dev/null 2>&1; then
        say "Bitwarden 項目 '$bw_item' は既に存在します。"
      else
        say "Bitwarden 項目 '$bw_item' を新規作成します（40 文字の生成パスフレーズ＝restic 暗号化鍵）。"
        if ! confirm "新しい restic 鍵を生成して '$bw_item' として保存しますか？"; then
          die "中断しました。手動作成する場合: rbw generate 40 $bw_item"
        fi
        rbw generate 40 "$bw_item"
        rbw sync >/dev/null || true
        if ! rbw get "$bw_item" >/dev/null 2>&1; then
          die "生成後に項目 '$bw_item' を読み取れませんでした。"
        fi
        say "鍵を Bitwarden の項目 '$bw_item' へ保存しました。"
      fi

      "${printRcloneBitwardenFields}" "$remote_name" "$bw_item"

      # Smoke-check: restic can decrypt the password command path via wrapper.
      if command -v backup >/dev/null 2>&1; then
        if backup snapshots >/dev/null 2>&1; then
          say "backup コマンドでリポジトリを開けました（既存スナップショット OK）。"
        else
          say "まだリポジトリは未初期化です（初回バックアップ前の正常な状態）。"
        fi
      fi

      # --- 3. First backup -----------------------------------------------
      step "3/3 初回バックアップ ($unit)"
      say "必要に応じて Google Drive 上に restic リポジトリを自動初期化します (initialize = true)。"
      if confirm "$unit を今すぐ開始しますか（sudo を求める場合があります）？"; then
        if systemctl --quiet is-active "$unit" 2>/dev/null; then
          say "$unit は既に実行中です。"
        elif systemctl start "$unit" 2>/dev/null; then
          say "$unit を開始しました。"
        else
          sudo systemctl start "$unit"
          say "$unit を開始しました（sudo 経由）。"
        fi
        say "ログ確認:"
        say "  backup log"
      else
        say "スキップしました。あとで開始するには:"
        say "  backup run"
        say "  backup log"
      fi

      say ""
      say "完了です。以後の確認・部分復元:"
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
    # caches/extensions, Firefox storage) and HM/Nix links.
    # Login password (/etc/shadow) is intentionally not staged.
    # ~/MySettings (flake checkout, including .git / uncommitted work) is kept.
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
      # Also exclude steam.sh (and bootstrap.tar.xz): bin_steam.sh treats
      # executable steam.sh as "already bootstrapped" and skips extracting
      # ubuntu12_32, causing startup to fail if ubuntu12_32 is excluded.
      "/home/${user}/.local/share/Steam/steam.sh"
      "/home/${user}/.local/share/Steam/bootstrap.tar.xz"
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
          fail_hint="GDrive OAuth失効。ConsoleでPublish後: backup reconnect"
        elif journalctl -u ${backupUnit} -n 40 -o cat --no-pager 2>/dev/null \
          | grep -Eqi 'pinentry cancelled|Resolving password failed'; then
          fail_hint="rbw がロック。先に: backup unlock-key"
        fi
        ${resticPanel} set "バックアップ失敗" "$fail_hint" failed || true
        ${resticNotify} critical "バックアップ失敗" "$fail_hint" || true
      fi
      # Leave the final panel label briefly; progress unit EXIT trap also clears.
      sleep 8
      ${resticPanel} clear || true
    '';

    # CLI: `backup` (see resticBackupCmd) — e.g.:
    #   backup setup | unlock-key | run | log | about | reconnect
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
