#!/usr/bin/env bash
# Restore the existing home backup before rebuilding NixOS.

usage() {
  cat <<'EOF'
Usage: ./scripts/restore-on-nixos.sh [EXTRACT_DIR]

Run as user mitac on the target NixOS machine (without sudo).
Missing tools (restic, rclone, jq) are fetched via nix shell.

Source: rclone:gdrive:restic/mitac-home (existing encrypted backup)
Default (no arguments):
  Verifies with restic --verify in temporary /var/tmp staging, then restores
  all backed-up files directly to their original locations:
    - Home: /home/mitac (overwrites existing files; keeps newly authenticated
      rclone.conf only when OAuth was configured/reconnected in this run)
    - System state (via sudo): /etc/NetworkManager/system-connections,
      /var/lib/bluetooth, /var/lib/cloudflare-warp, /var/lib/tailscale
With EXTRACT_DIR (new absolute directory path):
  Extracts and verifies into EXTRACT_DIR only without touching /home or /etc.

Prerequisites: check Bitwarden item 'restic-home' on another device.
If gdrive: or RESTIC_PASSWORD* is missing, prompts interactively for:
  1. Google OAuth client_id
  2. Google OAuth client_secret
  3. Google OAuth refresh_token (or token JSON; Enter = interactive OAuth)
  4. Encryption password (password field of restic-home)

Existing RCLONE_CONFIG (~/.config/rclone/rclone.conf or ~/.rclone.conf) and
RESTIC_PASSWORD / RESTIC_PASSWORD_FILE / RESTIC_PASSWORD_COMMAND are honored.
EOF
}

GDRIVE_CONFIGURED_THIS_RUN=0

fail() { printf '%s\n' "$*" >&2; exit 1; }

check_platform() {
  [[ -f /etc/NIXOS ]] || fail 'Run this script on a NixOS machine.'
  [[ $(id -un) == mitac ]] || fail 'Run as user mitac (without sudo).'
}

trim_ws() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

read_trimmed() {
  local line
  IFS= read -r line || return 1
  trim_ws "$line"
}

run_sudo() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

move_tree() {
  local src=${1%/} dst=${2%/}
  [[ -d $src ]] || return 0

  if [[ -L $dst || ( -e $dst && ! -d $dst ) ]]; then
    rm -f -- "$dst"
  fi
  mkdir -p -- "$dst"

  local -a dirs=() modes=() mtimes=()
  local dir rel target mode mtime
  while IFS= read -r -d '' dir; do
    rel=${dir#"$src"}
    target="${dst}${rel}"
    mode=$(stat -c '%a' -- "$dir")
    mtime=$(stat -c '%y' -- "$dir")
    dirs+=("$rel")
    modes+=("$mode")
    mtimes+=("$mtime")

    if [[ -L $target || ( -e $target && ! -d $target ) ]]; then
      rm -f -- "$target"
    fi
    mkdir -p -- "$target"
    chmod u+rwx -- "$dir" "$target"
  done < <(find "$src" -type d -print0)

  local entry
  while IFS= read -r -d '' entry; do
    rel=${entry#"$src"}
    target="${dst}${rel}"
    if [[ -d $target && ! -L $target ]]; then
      chmod -R u+rwx -- "$target" 2>/dev/null || true
      rm -rf -- "$target"
    fi
    mv -fT -- "$entry" "$target"
  done < <(find "$src" -mindepth 1 ! -type d -print0)

  local i
  for (( i = ${#dirs[@]} - 1; i >= 0; i-- )); do
    rel=${dirs[i]}
    mode=${modes[i]}
    mtime=${mtimes[i]}
    target="${dst}${rel}"
    chmod "$mode" -- "$target"
    touch -d "$mtime" -- "$target"
    rmdir -- "${src}${rel}"
  done
}

dir_has_entries() {
  local dir=$1
  [[ -d $dir ]] && [[ -n $(find "$dir" -mindepth 1 -maxdepth 1 -print -quit) ]]
}

reload_unit_if_active() {
  local unit=$1
  if command -v systemctl >/dev/null && [[ -d /run/systemd/system ]]; then
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      run_sudo systemctl restart "$unit" || true
    fi
  fi
}

restore_system_state() {
  local stage_sys=${1%/} root_prefix=${2%/}
  [[ -d $stage_sys ]] || return 0

  local -a entries=(
    "nm-connections|${root_prefix}/etc/NetworkManager/system-connections|600|nmcli"
    "bluetooth|${root_prefix}/var/lib/bluetooth||bluetooth.service"
    "cloudflare-warp|${root_prefix}/var/lib/cloudflare-warp||cloudflare-warp.service"
    "tailscale|${root_prefix}/var/lib/tailscale||tailscaled.service"
  )

  local entry sub dest fmode reload_target src_dir prompted=0
  for entry in "${entries[@]}"; do
    IFS='|' read -r sub dest fmode reload_target <<<"$entry"
    src_dir="${stage_sys}/${sub}"
    if ! dir_has_entries "$src_dir"; then
      continue
    fi
    if (( prompted == 0 )); then
      printf '\nApplying system state via sudo...\n' >&2
      prompted=1
    fi
    run_sudo mkdir -p -- "$dest"
    run_sudo chmod 700 -- "$dest"
    run_sudo cp -a --remove-destination -- "${src_dir}/." "${dest}/"
    run_sudo chown -R root:root -- "$dest"
    if [[ -n $fmode ]]; then
      run_sudo find "$dest" -type f -exec chmod "$fmode" {} +
    fi
    if [[ $reload_target == nmcli ]]; then
      if command -v nmcli >/dev/null && [[ -d /run/systemd/system ]] &&
         systemctl is-active --quiet NetworkManager.service 2>/dev/null; then
        run_sudo nmcli connection reload || true
      fi
    elif [[ -n $reload_target ]]; then
      reload_unit_if_active "$reload_target"
    fi
  done
}

normalize_token_input() {
  local raw=$1
  if [[ -z $raw ]]; then
    return 0
  fi
  if [[ $raw == \{* ]]; then
    jq -ce '
      select(type == "object")
      | select(
          ((.refresh_token // "") | (type == "string" and length > 0))
          or ((.access_token // "") | (type == "string" and length > 0))
        )
      | . + (
          if (.refresh_token // "") != "" then
            {
              access_token: (if (.access_token // "") != "" then .access_token else "x" end),
              token_type: (if (.token_type // "") != "" then .token_type else "Bearer" end),
              expiry: (if (.expiry // "") != "" then .expiry else "2000-01-01T00:00:00Z" end)
            }
          else
            {}
          end
        )
    ' <<<"$raw" 2>/dev/null
    return $?
  fi
  jq -nc --arg rt "$raw" \
    '{access_token:"x",token_type:"Bearer",refresh_token:$rt,expiry:"2000-01-01T00:00:00Z"}'
}

resolve_rclone_config() {
  if [[ -n ${RCLONE_CONFIG:-} ]]; then
    return 0
  fi
  local xdg_conf="${XDG_CONFIG_HOME:-$HOME/.config}/rclone/rclone.conf"
  if [[ -f $xdg_conf ]]; then
    export RCLONE_CONFIG=$xdg_conf
  elif [[ -f "$HOME/.rclone.conf" ]]; then
    export RCLONE_CONFIG="$HOME/.rclone.conf"
  else
    export RCLONE_CONFIG=$xdg_conf
  fi
}

probe_gdrive() {
  rclone about gdrive: --contimeout 10s --timeout 30s --retries 1 --low-level-retries 1
}

configure_gdrive() {
  local existing_id="" existing_secret="" dump_json=""
  if [[ -f $RCLONE_CONFIG ]]; then
    dump_json=$(rclone config dump 2>/dev/null || true)
    if [[ -n $dump_json ]]; then
      existing_id=$(jq -r '.gdrive.client_id // empty' <<<"$dump_json" 2>/dev/null || true)
      existing_secret=$(jq -r '.gdrive.client_secret // empty' <<<"$dump_json" 2>/dev/null || true)
    fi
  fi

  local client_id="" client_secret="" id_preview=""
  while [[ -z $client_id ]]; do
    if [[ -n $existing_id ]]; then
      id_preview=${existing_id:0:12}
      if (( ${#existing_id} > 12 )); then
        id_preview="${id_preview}..."
      fi
      printf 'Google OAuth client_id [Enter to keep %s]: ' "$id_preview" >&2
      client_id=$(read_trimmed) || fail 'Aborted while reading Google OAuth client_id.'
      if [[ -z $client_id ]]; then
        client_id=$existing_id
      fi
    else
      printf 'Google OAuth client_id: ' >&2
      client_id=$(read_trimmed) || fail 'Aborted while reading Google OAuth client_id.'
      if [[ -z $client_id ]]; then
        printf 'Google OAuth client_id is required.\n' >&2
      fi
    fi
  done

  while [[ -z $client_secret ]]; do
    if [[ -n $existing_secret ]]; then
      printf 'Google OAuth client_secret [Enter to keep existing]: ' >&2
      client_secret=$(read_trimmed) || fail 'Aborted while reading Google OAuth client_secret.'
      if [[ -z $client_secret ]]; then
        client_secret=$existing_secret
      fi
    else
      printf 'Google OAuth client_secret: ' >&2
      client_secret=$(read_trimmed) || fail 'Aborted while reading Google OAuth client_secret.'
      if [[ -z $client_secret ]]; then
        printf 'Google OAuth client_secret is required.\n' >&2
      fi
    fi
  done

  local raw_token="" token_json=""
  while true; do
    printf 'Google OAuth refresh_token (or token JSON; Enter for OAuth): ' >&2
    raw_token=$(read_trimmed) || fail 'Aborted while reading Google OAuth refresh_token.'
    if [[ -z $raw_token ]]; then
      token_json=""
      break
    fi
    if token_json=$(normalize_token_input "$raw_token") && [[ -n $token_json ]]; then
      break
    fi
    printf 'Invalid token JSON (expected object with refresh_token or access_token).\n' >&2
  done

  mkdir -p -- "$(dirname -- "$RCLONE_CONFIG")"
  touch -- "$RCLONE_CONFIG"
  chmod 600 -- "$RCLONE_CONFIG"

  if [[ -n $token_json ]]; then
    rclone config create gdrive drive \
      client_id "$client_id" \
      client_secret "$client_secret" \
      scope drive \
      token "$token_json" \
      config_refresh_token false \
      config_is_local false >/dev/null
    chmod 600 -- "$RCLONE_CONFIG"
  else
    rclone config create gdrive drive \
      client_id "$client_id" \
      client_secret "$client_secret" \
      scope drive \
      config_is_local false >/dev/null
    chmod 600 -- "$RCLONE_CONFIG"
    printf '\nStarting interactive OAuth for gdrive:.\n' >&2
    printf "If this machine has no browser, answer 'n' to 'Use auto config?' and authorize on another device.\n" >&2
    if ! rclone config reconnect gdrive:; then
      printf 'Interactive OAuth did not complete.\n' >&2
    fi
    chmod 600 -- "$RCLONE_CONFIG"
  fi
  GDRIVE_CONFIGURED_THIS_RUN=1
}

ensure_gdrive_remote() {
  GDRIVE_CONFIGURED_THIS_RUN=0
  resolve_rclone_config
  local remotes=""
  remotes=$(rclone listremotes 2>/dev/null || true)
  if ! grep -Fxq 'gdrive:' <<<"$remotes"; then
    [[ -t 0 ]] || fail "Remote gdrive: is missing in ${RCLONE_CONFIG}. Configure it first or run interactively."
    printf '\nRemote gdrive: is not configured (%s).\n' "$RCLONE_CONFIG" >&2
    printf "Check Bitwarden item 'restic-home' on another device and enter Google Drive OAuth values:\n" >&2
    configure_gdrive
  fi

  local action=""
  while ! probe_gdrive; do
    [[ -t 0 ]] || fail 'Failed to access Google Drive remote gdrive:.'
    printf '\nFailed to access Google Drive remote gdrive:.\n' >&2
    while true; do
      printf 'Choose: [r]e-enter values, [o]auth reconnect, [t]ry again, or [q]uit [r/o/t/q]: ' >&2
      action=$(read_trimmed) || fail 'Aborted while reading action.'
      case $action in
        r|R)
          configure_gdrive
          break
          ;;
        o|O)
          printf '\nStarting interactive OAuth reconnect for gdrive:.\n' >&2
          printf "If this machine has no browser, answer 'n' to 'Use auto config?' and authorize on another device.\n" >&2
          if ! rclone config reconnect gdrive:; then
            printf 'Interactive OAuth reconnect did not complete.\n' >&2
          fi
          chmod 600 -- "$RCLONE_CONFIG" 2>/dev/null || true
          GDRIVE_CONFIGURED_THIS_RUN=1
          break
          ;;
        t|T)
          break
          ;;
        q|Q)
          fail 'Aborted.'
          ;;
        *)
          printf 'Enter r, o, t, or q.\n' >&2
          ;;
      esac
    done
  done
}

ensure_tools() {
  local tool script
  local -a tools=(rclone restic jq)
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null; then
      command -v nix >/dev/null || fail 'Nix is required to fetch restore tools.'
      script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"
      printf 'Fetching restore tools via nix shell...\n'
      # The inner shell expands its own arguments and tool names.
      # shellcheck disable=SC2016
      exec nix --extra-experimental-features 'nix-command flakes' shell \
        nixpkgs#restic nixpkgs#rclone nixpkgs#jq \
        --command bash -c '
          for tool in restic rclone jq; do
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
  local explicit_target=${1:-}
  local root_prefix=${RESTORE_ROOT:-/}
  root_prefix=${root_prefix%/}
  local stage_parent=${RESTORE_STAGE_PARENT:-/var/tmp}
  local target="" parent=""

  if [[ -n $explicit_target ]]; then
    target=$explicit_target
    [[ $target == /* ]] || fail 'Target path must be absolute. See --help.'
    [[ ! -e $target && ! -L $target ]] || fail "Target already exists. Choose a new directory: $target"
    parent=$(dirname -- "$target")
    [[ -d $parent && -w $parent ]] || fail "Parent directory is not writable: $parent"
  else
    parent=$stage_parent
    [[ -d $parent && -w $parent ]] || fail "Staging parent directory is not writable: $parent"
  fi

  check_platform
  ensure_tools "$@"
  ensure_gdrive_remote

  export RESTIC_REPOSITORY=rclone:gdrive:restic/mitac-home

  # Let restic compare timestamps, then pin the snapshot before checking its size.
  local snapshot_id="" snapshots_json="" stats required_bytes available_bytes
  if [[ ! -v RESTIC_PASSWORD && -z ${RESTIC_PASSWORD_FILE:-} && -z ${RESTIC_PASSWORD_COMMAND:-} ]]; then
    [[ -t 0 ]] || fail 'Set RESTIC_PASSWORD, RESTIC_PASSWORD_FILE, or RESTIC_PASSWORD_COMMAND, or run interactively.'
    local pw="" retry=""
    while true; do
      printf "Enter restic encryption password (Bitwarden item 'restic-home', input hidden): " >&2
      IFS= read -rs pw || fail 'Aborted while reading restic encryption password.'
      printf '\n' >&2
      if [[ -z $pw ]]; then
        printf 'Password cannot be empty.\n' >&2
        continue
      fi
      export RESTIC_PASSWORD=$pw
      if snapshots_json=$(restic snapshots --json latest); then
        break
      fi
      printf 'Failed to open restic repository with entered password.\n' >&2
      printf 'Retry password? [Y/n] ' >&2
      retry=$(read_trimmed) || fail 'Aborted while reading choice.'
      case $retry in
        ''|y|Y|yes|YES) continue ;;
        *)
          unset RESTIC_PASSWORD
          fail 'Aborted.'
          ;;
      esac
    done
  else
    snapshots_json=$(restic snapshots --json latest)
  fi
  snapshot_id=$(jq -er '.[0].id // empty' <<<"$snapshots_json") || fail 'No snapshot found to restore.'
  [[ $snapshot_id =~ ^[0-9a-f]{64}$ ]] || fail 'No snapshot found to restore.'
  restic snapshots "$snapshot_id"
  stats=$(restic stats "$snapshot_id" --mode restore-size --json)
  required_bytes=$(jq -er '.total_size | select(type == "number" and . >= 0) | floor' <<<"$stats")
  printf 'Required restore size: %s bytes\n' "$required_bytes"
  df -h -- "$parent"
  available_bytes=$(df --output=avail -B1 -- "$parent" | tail -n 1)
  (( available_bytes >= required_bytes )) || fail 'Insufficient free disk space. Pass a new target directory on another disk.'

  if [[ -n $explicit_target ]]; then
    # Extract to an explicit directory only without modifying /home or /etc.
    mkdir -m 700 -- "$target"
    restic restore "$snapshot_id" --target "$target" --verify
    printf '%s\n' "$snapshot_id" > "$target/.restored-snapshot-id"
    printf '\nRestore and verification completed.\n'
    printf 'Extracted to: %s\n' "$target"
    printf 'Home: %s/home/mitac\n' "$target"
    printf 'System state: %s/run/restic-backups-home/system\n' "$target"
    printf 'Fonts: %s/home/mitac/Documents/hiragino-otf\n' "$target"
    return 0
  fi

  local stage_dir
  stage_dir=$(mktemp -d "${stage_parent%/}/restore-mitac-XXXXXXXX")
  chmod 700 -- "$stage_dir"
  restic restore "$snapshot_id" --target "$stage_dir" --verify

  local preserved_rclone=""
  if (( GDRIVE_CONFIGURED_THIS_RUN == 1 )) && [[ -f $RCLONE_CONFIG ]]; then
    preserved_rclone="${stage_dir}/.preserved-rclone.conf"
    cp -p -- "$RCLONE_CONFIG" "$preserved_rclone"
    chmod 600 -- "$preserved_rclone"
  fi

  local target_home="${root_prefix}/home/mitac"
  if [[ -d "${stage_dir}/home/mitac" ]]; then
    move_tree "${stage_dir}/home/mitac" "$target_home"
  fi
  if [[ -n $preserved_rclone && -f $preserved_rclone ]]; then
    mkdir -p -- "$(dirname -- "$RCLONE_CONFIG")"
    cp -f --remove-destination -- "$preserved_rclone" "$RCLONE_CONFIG"
    chmod 600 -- "$RCLONE_CONFIG"
    rm -f -- "$preserved_rclone"
  fi

  restore_system_state "${stage_dir}/run/restic-backups-home/system" "$root_prefix"
  rm -rf -- "$stage_dir"

  printf '\nRestore and verification completed.\n'
  printf 'Snapshot: %s\n' "$snapshot_id"
  printf 'Home: %s\n' "$target_home"
  printf 'System state: %s/etc/NetworkManager/system-connections, %s/var/lib/{bluetooth,cloudflare-warp,tailscale}\n' "$root_prefix" "$root_prefix"
  printf 'Fonts (if backed up): %s/Documents/hiragino-otf\n' "$target_home"
  printf 'If rebuilding NixOS from ~/MySettings, add --impure when Documents/hiragino-otf exists.\n'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
