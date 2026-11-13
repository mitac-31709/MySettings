#!/usr/bin/env bash
# Restore the existing home backup before rebuilding NixOS.

usage() {
  cat <<'EOF'
Usage: ./scripts/restore-on-nixos.sh [NEW_TARGET_DIR]

Run as user mitac on the target NixOS machine (without sudo).
Missing tools (restic, rclone, rbw, jq, pinentry-curses) are fetched via nix shell.

Source: gdrive:restic/mitac-home (existing encrypted backup)
Target: /var/tmp/restore-mitac-YYYYMMDD-HHMMSS (default)
Restores the full latest snapshot and checks it with --verify.
Refuses an existing target path; does not overwrite /home or /etc directly.

Prerequisites: rclone gdrive remote and existing restic-home item in Bitwarden.
Existing RESTIC_PASSWORD_FILE / RESTIC_PASSWORD_COMMAND env vars are also honored.
EOF
}

fail() { printf '%s\n' "$*" >&2; exit 1; }

check_platform() {
  [[ -f /etc/NIXOS ]] || fail 'Run this script on a NixOS machine.'
  [[ $(id -un) == mitac ]] || fail 'Run as user mitac (without sudo).'
}

ensure_tools() {
  local tool script
  local -a tools=(rclone restic jq)
  if [[ ! -v RESTIC_PASSWORD && -z ${RESTIC_PASSWORD_FILE:-} && -z ${RESTIC_PASSWORD_COMMAND:-} ]]; then
    tools+=(rbw pinentry-curses)
  fi
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null; then
      command -v nix >/dev/null || fail 'Nix is required to fetch restore tools.'
      script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/restore-on-nixos.sh"
      printf 'Fetching restore tools via nix shell...\n'
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
  (( $# <= 1 )) || fail 'Too many arguments. See --help.'
  local target=${1:-"/var/tmp/restore-mitac-$(date +%Y%m%d-%H%M%S)"}
  [[ $target == /* ]] || fail 'Target path must be absolute. See --help.'
  [[ ! -e $target && ! -L $target ]] || fail "Target already exists. Choose a new directory: $target"
  local parent
  parent=$(dirname -- "$target")
  [[ -d $parent && -w $parent ]] || fail "Parent directory is not writable: $parent"
  check_platform
  ensure_tools "$@"

  if [[ -z ${RCLONE_CONFIG:-} && -f "$HOME/.config/rclone/rclone.conf" ]]; then
    export RCLONE_CONFIG="$HOME/.config/rclone/rclone.conf"
  fi
  local remotes
  remotes=$(rclone listremotes)
  grep -Fxq 'gdrive:' <<<"$remotes" ||
    fail 'Remote gdrive: is missing. Configure rclone gdrive: first (see README).'
  rclone about gdrive: --contimeout 10s --timeout 30s --retries 1 --low-level-retries 1

  export RESTIC_REPOSITORY=rclone:gdrive:restic/mitac-home
  if [[ ! -v RESTIC_PASSWORD && -z ${RESTIC_PASSWORD_FILE:-} && -z ${RESTIC_PASSWORD_COMMAND:-} ]]; then
    export RESTIC_PASSWORD_COMMAND='rbw get restic-home'
  fi

  # Let restic compare timestamps, then pin the snapshot before checking its size.
  local snapshot_id stats required_bytes available_bytes
  snapshot_id=$(restic snapshots --json latest | jq -er '.[0].id // empty')
  [[ $snapshot_id =~ ^[0-9a-f]{64}$ ]] || fail 'No snapshot found to restore.'
  restic snapshots "$snapshot_id"
  stats=$(restic stats "$snapshot_id" --mode restore-size --json)
  required_bytes=$(jq -er '.total_size | select(type == "number" and . >= 0) | floor' <<<"$stats")
  printf 'Required restore size: %s bytes\n' "$required_bytes"
  df -h -- "$parent"
  available_bytes=$(df --output=avail -B1 -- "$parent" | tail -n 1)
  (( available_bytes >= required_bytes )) || fail 'Insufficient free disk space. Pass a new target directory on another disk.'

  # The default target is outside the daily home backup; mkdir also rejects races.
  mkdir -m 700 -- "$target"
  restic restore "$snapshot_id" --target "$target" --verify
  printf '%s\n' "$snapshot_id" > "$target/.restored-snapshot-id"
  printf '\nRestore and verification completed.\n'
  printf 'Home: %s/home/mitac\n' "$target"
  printf 'System state: %s/run/restic-backups-home/system\n' "$target"
  printf 'Fonts: %s/home/mitac/Documents/hiragino-otf\n' "$target"
  printf 'Inspect restored files before copying anything into /home or /etc and rebuilding NixOS.\n'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
