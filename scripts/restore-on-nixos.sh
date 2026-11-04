#!/usr/bin/env bash
# Restore the existing home backup before rebuilding NixOS.

usage() {
  cat <<'EOF'
使い方: ./scripts/restore-on-nixos.sh [新しい復元先ディレクトリ]

実機の NixOS で mitac ユーザーとして実行してください。
必要ツールがなければ nix shell で restic / rclone / rbw / jq などを取得します。

復元元: gdrive:restic/mitac-home（既存の暗号化バックアップ）
復元先: /var/tmp/restore-mitac-日時（省略時）
最新スナップショット全体を復元し、--verify で内容を検証します。
既存のディレクトリは指定できません。実際の /home や /etc への反映は行いません。

事前準備: rclone の gdrive リモートと、Bitwarden の既存 restic-home 鍵。
RESTIC_PASSWORD_FILE / RESTIC_PASSWORD_COMMAND などの既存設定も使えます。
EOF
}

fail() { printf '%s\n' "$*" >&2; exit 1; }

check_platform() {
  [[ -f /etc/NIXOS ]] || fail '実機の NixOS 上で実行してください。'
  [[ $(id -un) == mitac ]] || fail 'mitac ユーザーで実行してください（sudo は付けません）。'
}

ensure_tools() {
  local tool script
  local -a tools=(rclone restic jq)
  if [[ ! -v RESTIC_PASSWORD && -z ${RESTIC_PASSWORD_FILE:-} && -z ${RESTIC_PASSWORD_COMMAND:-} ]]; then
    tools+=(rbw pinentry-curses)
  fi
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null; then
      command -v nix >/dev/null || fail '必要ツールを取得するため Nix が必要です。'
      script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/restore-on-nixos.sh"
      printf '復元用ツールを nix shell で取得します。\n'
      # The inner shell expands its own arguments and tool names.
      # shellcheck disable=SC2016
      exec nix --extra-experimental-features 'nix-command flakes' shell \
        nixpkgs#restic nixpkgs#rclone nixpkgs#rbw nixpkgs#jq nixpkgs#pinentry-curses \
        --command bash -c '
          for tool in restic rclone rbw jq pinentry-curses; do
            command -v "$tool" >/dev/null || exit 1
          done
          exec bash "$@"
        ' restore-tools "$script" "$@"
    fi
  done
}

main() {
  set -euo pipefail
  umask 077
  if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    usage
    return 0
  fi
  (( $# <= 1 )) || fail '引数が多すぎます。--help を参照してください。'
  local target=${1:-"/var/tmp/restore-mitac-$(date +%Y%m%d-%H%M%S)"}
  [[ $target == /* ]] || fail '復元先は絶対パスで指定してください。--help を参照してください。'
  [[ ! -e $target && ! -L $target ]] || fail "復元先が既にあります。別の新しいディレクトリを指定してください: $target"
  local parent
  parent=$(dirname -- "$target")
  [[ -d $parent && -w $parent ]] || fail "復元先の親ディレクトリに書き込めません: $parent"
  check_platform
  ensure_tools "$@"

  if [[ -z ${RCLONE_CONFIG:-} && -f "$HOME/.config/rclone/rclone.conf" ]]; then
    export RCLONE_CONFIG="$HOME/.config/rclone/rclone.conf"
  fi
  local remotes
  remotes=$(rclone listremotes)
  grep -Fxq 'gdrive:' <<<"$remotes" ||
    fail 'gdrive リモートがありません。README の「OS ビルド前に実機へ復元」を参照してください。'
  rclone about gdrive: --contimeout 10s --timeout 30s --retries 1 --low-level-retries 1

  export RESTIC_REPOSITORY=rclone:gdrive:restic/mitac-home
  if [[ ! -v RESTIC_PASSWORD && -z ${RESTIC_PASSWORD_FILE:-} && -z ${RESTIC_PASSWORD_COMMAND:-} ]]; then
    export RESTIC_PASSWORD_COMMAND='rbw get restic-home'
  fi

  # Let restic compare timestamps, then pin the snapshot before checking its size.
  local snapshot_id stats required_bytes available_bytes
  snapshot_id=$(restic snapshots --json latest | jq -er '.[0].id // empty')
  [[ $snapshot_id =~ ^[0-9a-f]{64}$ ]] || fail '復元可能なスナップショットが見つかりません。'
  restic snapshots "$snapshot_id"
  stats=$(restic stats "$snapshot_id" --mode restore-size --json)
  required_bytes=$(jq -er '.total_size | select(type == "number" and . >= 0) | floor' <<<"$stats")
  printf '復元データ容量: %s bytes\n' "$required_bytes"
  df -h -- "$parent"
  available_bytes=$(df --output=avail -B1 -- "$parent" | tail -n 1)
  (( available_bytes >= required_bytes )) || fail '空き容量が不足しています。別ディスク上の新しい復元先を指定してください。'

  # The default target is outside the daily home backup; mkdir also rejects races.
  mkdir -m 700 -- "$target"
  restic restore "$snapshot_id" --target "$target" --verify
  printf '%s\n' "$snapshot_id" > "$target/.restored-snapshot-id"
  printf '\n全体の復元・検証が完了しました。\n'
  printf 'ホーム: %s/home/mitac\n' "$target"
  printf 'システム状態: %s/run/restic-backups-home/system\n' "$target"
  printf 'フォント: %s/home/mitac/Documents/hiragino-otf\n' "$target"
  printf '実際の /home や /etc への反映と OS ビルドは、復元内容を確認した後に進めてください。\n'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
