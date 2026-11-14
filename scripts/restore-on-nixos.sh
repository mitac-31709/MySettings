#!/usr/bin/env bash
# OS ビルド前（初期日本語 LXQt 等）または再構築後に /home バックアップを復元するスクリプト。

usage() {
  cat <<'EOF'
使い方: ./scripts/restore-on-nixos.sh [EXTRACT_DIR]

対象 NixOS マシン上でユーザー mitac として実行します（sudo は付けない）。
不足ツール（restic / rclone / jq / python3 / rbw / pinentry）は nix shell で自動取得します。

復元元: rclone:gdrive:restic/mitac-home
既定（引数なし）:
  一時領域（/home/mitac と同一ファイルシステムを優先: 同一 FS なら /var/tmp、
  別パーティション／Btrfs 別サブボリューム時は /home/mitac 内の隠し領域）で
  restic --verify による検証を完了させた後、元の位置へ上書き復元します:
    - ホーム: /home/mitac（既存ファイルを上書き。ただし今回の実行中に
      新規取得・再認証・Bitwarden 反映した rclone.conf のみ保持）
    - システム状態（必要時のみ sudo）: /etc/NetworkManager/system-connections,
      /var/lib/bluetooth, /var/lib/cloudflare-warp, /var/lib/tailscale
EXTRACT_DIR 指定時（未作成の絶対パス）:
  /home や /etc には触れず、EXTRACT_DIR 配下への展開と検証のみを行います。

Bitwarden (rbw) 自動入力とフォールバック:
  - gdrive: リモートまたは暗号化パスワードが未設定の場合、Bitwarden の項目
    'restic-home'（RBW_ITEM で変更可）から自動取得を試みます。
  - rbw が未設定なら公式 EU クラウド（home/programs.nix と同じ設定。
    メール既定: mitac31709@gmail.com、pinentry は GUI で pinentry-qt /
    非 GUI で pinentry-curses）を自動設定してからログイン／ロック解除します。
  - 項目 'restic-home' のパスワード欄を restic 暗号化パスワードとして使用し、
    カスタムフィールドまたはメモ欄の client_id / client_secret /
    refresh_token（または token JSON）から gdrive: を自動構成します。
  - 一部または全部が未登録、あるいは手動入力を選んだ場合は、足りない値だけ
    対話入力またはブラウザ OAuth（rclone config reconnect gdrive:）で補えます。

既存の RCLONE_CONFIG（~/.config/rclone/rclone.conf / ~/.rclone.conf）や
RESTIC_PASSWORD / RESTIC_PASSWORD_FILE / RESTIC_PASSWORD_COMMAND がある場合は
そちらを優先します（RESTORE_NO_RBW=1 で rbw 利用を抑止可能）。
環境変数 RBW_ITEM / RBW_EMAIL / RBW_BASE_URL も利用できます。
EOF
}

GDRIVE_CONFIGURED_THIS_RUN=0
RBW_ITEM=${RBW_ITEM:-restic-home}
RBW_FETCHED=0
RBW_DECLINED=0
RBW_CLIENT_ID=""
RBW_CLIENT_SECRET=""
RBW_TOKEN_JSON=""
RBW_PASSWORD=""

fail() { printf '%s\n' "$*" >&2; exit 1; }

check_platform() {
  [[ -f /etc/NIXOS ]] || fail 'このスクリプトは NixOS マシン上で実行してください。'
  [[ $(id -un) == mitac ]] || fail 'ユーザー mitac で実行してください（sudo は付けない）。'
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

move_tree_python() {
  local src=$1 dst=$2 protect_path=${3:-}
  python3 - "$src" "$dst" "$protect_path" <<'PYEOF'
import errno
import os
import shutil
import stat
import sys
import tempfile
import time

if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

src_root = os.path.abspath(sys.argv[1])
dst_root = os.path.abspath(sys.argv[2])
protect_abs = os.path.abspath(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] else ""
force_exdev = os.environ.get("_RESTORE_TEST_FORCE_EXDEV") == "1"

if not os.path.isdir(src_root) or os.path.islink(src_root):
    sys.exit(0)


def chmod_min_u_rwx(path, mode):
    if (mode & 0o700) != 0o700:
        os.chmod(path, mode | 0o700)


def rmtree_force(path):
    stack = [path]
    dirs = []
    while stack:
        cur = stack.pop()
        try:
            st = os.lstat(cur)
        except FileNotFoundError:
            continue
        if not stat.S_ISDIR(st.st_mode):
            os.unlink(cur)
            continue
        chmod_min_u_rwx(cur, stat.S_IMODE(st.st_mode))
        dirs.append(cur)
        with os.scandir(cur) as it:
            for entry in it:
                if entry.is_dir(follow_symlinks=False):
                    stack.append(entry.path)
                else:
                    try:
                        os.unlink(entry.path)
                    except PermissionError:
                        os.chmod(cur, 0o700)
                        os.unlink(entry.path)
    for d in reversed(dirs):
        os.rmdir(d)


def remove_existing_non_dir_target(path):
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return
    if stat.S_ISDIR(st.st_mode):
        rmtree_force(path)
    else:
        os.unlink(path)


def copy_xattrs_best_effort(src_path, dst_path):
    if not hasattr(os, "listxattr"):
        return
    try:
        names = os.listxattr(src_path, follow_symlinks=False)
    except OSError:
        return
    for name in names:
        try:
            val = os.getxattr(src_path, name, follow_symlinks=False)
            os.setxattr(dst_path, name, val, follow_symlinks=False)
        except OSError:
            pass


def move_cross_fs(src_path, dst_path, link_map):
    st = os.lstat(src_path)
    mode = stat.S_IMODE(st.st_mode)
    times = (st.st_atime_ns, st.st_mtime_ns)
    remove_existing_non_dir_target(dst_path)

    if stat.S_ISLNK(st.st_mode):
        os.symlink(os.readlink(src_path), dst_path)
        try:
            os.utime(dst_path, ns=times, follow_symlinks=False)
        except (NotImplementedError, OSError):
            pass
        os.unlink(src_path)
        return

    ino_key = (st.st_dev, st.st_ino)
    prev = link_map.get(ino_key)
    if prev is not None:
        try:
            os.link(prev, dst_path)
            os.unlink(src_path)
            return
        except OSError:
            pass

    if stat.S_ISREG(st.st_mode):
        dst_parent = os.path.dirname(dst_path) or "."
        fd, tmp_path = tempfile.mkstemp(prefix=".restore-tmp-", dir=dst_parent)
        os.close(fd)
        try:
            try:
                shutil.copyfile(src_path, tmp_path)
            except PermissionError:
                os.chmod(src_path, mode | 0o400)
                shutil.copyfile(src_path, tmp_path)
            copy_xattrs_best_effort(src_path, tmp_path)
            os.utime(tmp_path, ns=times)
            os.chmod(tmp_path, mode)
            os.replace(tmp_path, dst_path)
        except BaseException:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise
        if st.st_nlink > 1:
            link_map[(st.st_dev, st.st_ino)] = dst_path
        os.unlink(src_path)
        return

    if stat.S_ISFIFO(st.st_mode):
        os.mkfifo(dst_path, mode)
        os.utime(dst_path, ns=times)
        os.chmod(dst_path, mode)
        os.unlink(src_path)
        return

    # Character/block devices or sockets: replicate node if permitted.
    try:
        os.mknod(dst_path, st.st_mode, st.st_rdev)
        os.utime(dst_path, ns=times)
        os.chmod(dst_path, mode)
    except OSError:
        pass
    os.unlink(src_path)


def move_entry(src_path, dst_path, link_map):
    if protect_abs and os.path.abspath(dst_path) == protect_abs:
        remove_existing_non_dir_target(src_path)
        return
    if force_exdev:
        move_cross_fs(src_path, dst_path, link_map)
        return
    try:
        os.replace(src_path, dst_path)
    except IsADirectoryError:
        rmtree_force(dst_path)
        os.replace(src_path, dst_path)
    except OSError as exc:
        if exc.errno == errno.EXDEV:
            move_cross_fs(src_path, dst_path, link_map)
        else:
            raise


# Ensure root destination exists as a real directory (not a symlink or file).
try:
    st_root_dst = os.lstat(dst_root)
    if not stat.S_ISDIR(st_root_dst.st_mode):
        os.unlink(dst_root)
        os.makedirs(dst_root, mode=0o700, exist_ok=True)
except FileNotFoundError:
    os.makedirs(dst_root, mode=0o700, exist_ok=True)

is_tty = sys.stderr.isatty()
last_report = time.monotonic()
reported_inline = False
moved_files = 0
moved_dirs = 0
dir_records = []
link_map = {}


def maybe_report_progress():
    global last_report, reported_inline
    now = time.monotonic()
    if now - last_report < 1.5:
        return
    if is_tty:
        sys.stderr.write(
            f"\r  移動中: ファイル {moved_files} 件・ディレクトリ {moved_dirs} 件..."
        )
        reported_inline = True
    else:
        sys.stderr.write(
            f"  移動中: ファイル {moved_files} 件・ディレクトリ {moved_dirs} 件...\n"
        )
    sys.stderr.flush()
    last_report = now


stack = [(src_root, dst_root)]
while stack:
    cur_src, cur_dst = stack.pop()
    if cur_dst != dst_root and protect_abs and os.path.abspath(cur_dst) == protect_abs:
        # Never overwrite an active staging directory placed inside dst_root.
        rmtree_force(cur_src)
        continue

    st_src = os.lstat(cur_src)
    orig_mode = stat.S_IMODE(st_src.st_mode)
    chmod_min_u_rwx(cur_src, orig_mode)

    if cur_dst != dst_root:
        try:
            st_dst = os.lstat(cur_dst)
            if not stat.S_ISDIR(st_dst.st_mode):
                os.unlink(cur_dst)
                os.mkdir(cur_dst, 0o700)
            else:
                chmod_min_u_rwx(cur_dst, stat.S_IMODE(st_dst.st_mode))
        except FileNotFoundError:
            os.mkdir(cur_dst, 0o700)
    else:
        st_dst = os.lstat(cur_dst)
        chmod_min_u_rwx(cur_dst, stat.S_IMODE(st_dst.st_mode))

    dir_records.append((cur_dst, orig_mode, st_src.st_atime_ns, st_src.st_mtime_ns, cur_src))
    moved_dirs += 1
    maybe_report_progress()

    sub_dirs = []
    non_dirs = []
    with os.scandir(cur_src) as it:
        for entry in it:
            if entry.is_dir(follow_symlinks=False):
                sub_dirs.append(entry.name)
            else:
                non_dirs.append(entry.name)

    for name in non_dirs:
        move_entry(os.path.join(cur_src, name), os.path.join(cur_dst, name), link_map)
        moved_files += 1
        maybe_report_progress()

    for name in reversed(sub_dirs):
        stack.append((os.path.join(cur_src, name), os.path.join(cur_dst, name)))

for cur_dst, orig_mode, atime_ns, mtime_ns, cur_src in reversed(dir_records):
    os.utime(cur_dst, ns=(atime_ns, mtime_ns))
    os.chmod(cur_dst, orig_mode)
    os.rmdir(cur_src)

if is_tty and reported_inline:
    sys.stderr.write(
        f"\r  移動完了: ファイル {moved_files} 件・ディレクトリ {moved_dirs} 件          \n"
    )
else:
    sys.stderr.write(
        f"  移動完了: ファイル {moved_files} 件・ディレクトリ {moved_dirs} 件\n"
    )
sys.stderr.flush()
PYEOF
}

move_tree_bash() {
  local src=${1%/} dst=${2%/} protect_path=${3:-}
  [[ -d $src ]] || return 0

  if [[ -L $dst || ( -e $dst && ! -d $dst ) ]]; then
    rm -f -- "$dst"
  fi
  mkdir -p -- "$dst"

  local -a dirs=() modes=() mtimes=() skipped_dirs=()
  local dir rel target mode mtime count=0
  while IFS= read -r -d '' dir; do
    rel=${dir#"$src"}
    target="${dst}${rel}"
    if [[ -n $protect_path && ( $target == "$protect_path" || $target == "$protect_path"/* ) ]]; then
      if [[ $target == "$protect_path" ]]; then
        skipped_dirs+=("$dir")
      fi
      continue
    fi
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
    if [[ -n $protect_path && ( $target == "$protect_path" || $target == "$protect_path"/* ) ]]; then
      rm -f -- "$entry"
      continue
    fi
    if [[ -d $target && ! -L $target ]]; then
      chmod -R u+rwx -- "$target" 2>/dev/null || true
      rm -rf -- "$target"
    fi
    mv -fT -- "$entry" "$target"
    count=$((count + 1))
    if (( count % 500 == 0 )); then
      printf '  移動中: %d 件...\n' "$count" >&2
    fi
  done < <(find "$src" -mindepth 1 ! -type d -print0)

  if (( ${#skipped_dirs[@]} > 0 )); then
    local sdir
    for sdir in "${skipped_dirs[@]}"; do
      chmod -R u+rwx -- "$sdir" 2>/dev/null || true
      rm -rf -- "$sdir"
    done
  fi

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
  printf '  移動完了: ファイル %d 件・ディレクトリ %d 件\n' "$count" "${#dirs[@]}" >&2
}

move_tree() {
  local src=${1%/} dst=${2%/} protect_path=${3:-}
  [[ -d $src ]] || return 0
  if command -v python3 >/dev/null 2>&1; then
    move_tree_python "$src" "$dst" "$protect_path"
  else
    move_tree_bash "$src" "$dst" "$protect_path"
  fi
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
      printf '\nsudo でシステム状態を反映します...\n' >&2
      prompted=1
    fi
    run_sudo mkdir -p -- "$dest"
    run_sudo chmod 700 -- "$dest"
    run_sudo cp -a --remove-destination -- "${src_dir}/." "${dest}/"
    run_sudo chown -R root:root -- "$dest"
    if [[ -n $fmode ]]; then
      run_sudo find "$dest" -type f -exec chmod "$fmode" {} +
    fi
    # Only reload/restart live host daemons when restoring directly into /.
    if [[ -z $root_prefix ]]; then
      if [[ $reload_target == nmcli ]]; then
        if command -v nmcli >/dev/null && [[ -d /run/systemd/system ]] &&
           systemctl is-active --quiet NetworkManager.service 2>/dev/null; then
          run_sudo nmcli connection reload || true
        fi
      elif [[ -n $reload_target ]]; then
        reload_unit_if_active "$reload_target"
      fi
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
  if [[ $raw == *[[:space:]]* ]]; then
    return 1
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

has_rbw() {
  [[ ${RESTORE_NO_RBW:-0} != 1 ]] && command -v rbw >/dev/null 2>&1
}

desired_pinentry_cmd() {
  if [[ -n ${DISPLAY:-} || -n ${WAYLAND_DISPLAY:-} ]]; then
    if command -v pinentry-qt >/dev/null 2>&1; then
      command -v pinentry-qt
      return 0
    fi
  fi
  if command -v pinentry-curses >/dev/null 2>&1; then
    command -v pinentry-curses
    return 0
  fi
  if command -v pinentry-qt >/dev/null 2>&1; then
    command -v pinentry-qt
    return 0
  fi
  if command -v pinentry >/dev/null 2>&1; then
    command -v pinentry
    return 0
  fi
  return 1
}

configured_pinentry_works() {
  command -v rbw >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local cfg p
  cfg=$(rbw config show 2>/dev/null || true)
  p=$(jq -r '.pinentry // empty' <<<"$cfg" 2>/dev/null || true)
  [[ -n $p && $p != pinentry ]] && command -v "$p" >/dev/null 2>&1
}

ensure_rbw_configured() {
  local rbw_conf="${XDG_CONFIG_HOME:-$HOME/.config}/rbw/config.json"
  local conf_ro=0
  if [[ -L $rbw_conf && ! -w $rbw_conf ]] || { [[ -e $rbw_conf && ! -w $rbw_conf ]]; }; then
    conf_ro=1
  fi

  local cfg_json
  cfg_json=$(rbw config show 2>/dev/null || printf '{}')
  if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$cfg_json"; then
    cfg_json='{}'
  fi

  local cur_email cur_base_url cur_identity_url cur_ui_url cur_notifications_url cur_pinentry
  cur_email=$(jq -r '.email // empty' <<<"$cfg_json" 2>/dev/null || true)
  cur_base_url=$(jq -r '.base_url // empty' <<<"$cfg_json" 2>/dev/null || true)
  cur_identity_url=$(jq -r '.identity_url // empty' <<<"$cfg_json" 2>/dev/null || true)
  cur_ui_url=$(jq -r '.ui_url // empty' <<<"$cfg_json" 2>/dev/null || true)
  cur_notifications_url=$(jq -r '.notifications_url // empty' <<<"$cfg_json" 2>/dev/null || true)
  cur_pinentry=$(jq -r '.pinentry // empty' <<<"$cfg_json" 2>/dev/null || true)

  local changed=0
  if [[ -z $cur_email ]]; then
    if (( conf_ro == 1 )); then
      printf 'rbw 設定ファイル (%s) が読み取り専用かつ未設定のため初期設定できません。\n' "$rbw_conf" >&2
      return 1
    fi
    local email=""
    if [[ -n ${RBW_EMAIL:-} ]]; then
      email=$RBW_EMAIL
    elif [[ -t 0 ]]; then
      printf 'Bitwarden メールアドレス [Enter で mitac31709@gmail.com]: ' >&2
      email=$(read_trimmed) || fail 'メールアドレスの入力が中断されました。'
      email=${email:-mitac31709@gmail.com}
    else
      return 1
    fi
    rbw config set email "$email"
    changed=1

    if [[ -z $cur_base_url ]]; then
      local target_base=${RBW_BASE_URL:-https://api.bitwarden.eu}
      rbw config set base_url "$target_base"
      if [[ $target_base == "https://api.bitwarden.eu" ]]; then
        [[ -n $cur_identity_url ]] || rbw config set identity_url "${RBW_IDENTITY_URL:-https://identity.bitwarden.eu}"
        [[ -n $cur_ui_url ]] || rbw config set ui_url "${RBW_UI_URL:-https://vault.bitwarden.eu}"
        [[ -n $cur_notifications_url ]] || rbw config set notifications_url "${RBW_NOTIFICATIONS_URL:-https://notifications.bitwarden.eu}"
      else
        [[ -z ${RBW_IDENTITY_URL:-} ]] || rbw config set identity_url "$RBW_IDENTITY_URL"
        [[ -z ${RBW_UI_URL:-} ]] || rbw config set ui_url "$RBW_UI_URL"
        [[ -z ${RBW_NOTIFICATIONS_URL:-} ]] || rbw config set notifications_url "$RBW_NOTIFICATIONS_URL"
      fi
      printf 'rbw を初期設定しました (email: %s, server: %s)。\n' "$email" "$target_base" >&2
    else
      printf 'rbw のメールアドレスを設定しました (%s)。\n' "$email" >&2
    fi
  fi

  if (( conf_ro == 0 )); then
    if [[ -z $cur_pinentry || $cur_pinentry == pinentry ]] || ! command -v "$cur_pinentry" >/dev/null 2>&1; then
      local target_pinentry=""
      if target_pinentry=$(desired_pinentry_cmd); then
        rbw config set pinentry "$target_pinentry"
        changed=1
      fi
    fi
  fi

  if (( changed == 1 )); then
    rbw stop-agent >/dev/null 2>&1 || true
  fi
  return 0
}

ensure_rbw_unlocked() {
  local force_prompt=${1:-0}
  if rbw unlocked >/dev/null 2>&1; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    return 1
  fi

  if (( force_prompt == 0 )); then
    printf "\nBitwarden (rbw) から項目 '%s' の設定・鍵を自動取得しますか？ [Y/n] " "$RBW_ITEM" >&2
    local reply=""
    reply=$(read_trimmed) || fail '入力が中断されました。'
    case $reply in
      ''|y|Y|yes|YES) ;;
      *)
        RBW_DECLINED=1
        return 1
        ;;
    esac
  fi

  ensure_rbw_configured || return 1

  local action=""
  while true; do
    if ! rbw unlocked >/dev/null 2>&1; then
      printf 'Bitwarden (rbw) へログイン／ロック解除します...\n' >&2
      if rbw login && rbw unlock; then
        :
      else
        printf '\nBitwarden (rbw) のログインまたはロック解除に失敗しました。\n' >&2
        printf '公式 Bitwarden サーバーでは初回のみ端末登録（rbw register + Personal API Key）が必要な場合があります。\n' >&2
        while true; do
          printf '選択: [r]bw register を実行して再試行, [l]ogin/unlock を再試行, [m]手動入力へ切替, [q]中止 [r/l/m/q]: ' >&2
          action=$(read_trimmed) || fail '操作選択が中断されました。'
          case $action in
            r|R)
              rbw register || true
              if rbw login && rbw unlock; then
                break
              fi
              printf 'ログインまたはロック解除に失敗しました。\n' >&2
              ;;
            l|L)
              if rbw login && rbw unlock; then
                break
              fi
              printf 'ログインまたはロック解除に失敗しました。\n' >&2
              ;;
            m|M)
              RBW_DECLINED=1
              return 1
              ;;
            q|Q)
              fail '中止しました。'
              ;;
            *)
              printf 'r, l, m, q のいずれかを入力してください。\n' >&2
              ;;
          esac
        done
      fi
    fi
    if rbw unlocked >/dev/null 2>&1; then
      break
    fi
  done
  return 0
}

clean_rbw_field_value() {
  local v
  v=$(trim_ws "$1")
  if [[ ${#v} -ge 2 ]]; then
    if [[ ( $v == \"*\" ) || ( $v == \'*\' ) ]]; then
      v=${v:1:${#v}-2}
      v=$(trim_ws "$v")
    fi
  fi
  case $v in
    ""|"(not set)"|"(未設定)"|"null"|"NULL"|"none"|"NONE")
      printf ''
      return 0
      ;;
    \<*\>)
      printf ''
      return 0
      ;;
  esac
  printf '%s' "$v"
}

rbw_extract_custom_field() {
  local target_norm=$1 json=$2
  jq -r --arg k "$target_norm" '
    [ .fields[]?
      | select((.name? // "" | tostring | ascii_downcase | gsub("[-_[:space:]]+"; "")) == $k)
      | (.value? // "" | tostring)
    ][0] // empty
  ' <<<"$json" 2>/dev/null || true
}

load_from_rbw() {
  local force_sync=${1:-0}
  has_rbw || return 1
  if (( force_sync == 0 )) && (( RBW_FETCHED == 1 )); then
    return 0
  fi
  if (( force_sync == 0 )) && (( RBW_DECLINED == 1 )); then
    return 1
  fi

  ensure_rbw_unlocked "$force_sync" || return 1
  if (( force_sync == 1 )); then
    rbw sync || printf '警告: rbw sync に失敗しました（ローカルキャッシュを参照します）。\n' >&2
  else
    rbw sync >/dev/null 2>&1 || true
  fi

  local raw_json=""
  if ! raw_json=$(rbw get --raw "$RBW_ITEM" 2>/dev/null) || [[ -z $raw_json ]]; then
    printf "警告: Bitwarden の項目 '%s' を取得できませんでした（項目名・rbw sync を確認してください）。\n" "$RBW_ITEM" >&2
    return 1
  fi
  if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$raw_json"; then
    printf "警告: Bitwarden の項目 '%s' の出力形式を解釈できませんでした。\n" "$RBW_ITEM" >&2
    return 1
  fi

  RBW_PASSWORD=$(jq -r '.data.password // empty' <<<"$raw_json" 2>/dev/null || true)

  local f_cid f_csec f_rt f_tok
  f_cid=$(clean_rbw_field_value "$(rbw_extract_custom_field clientid "$raw_json")")
  f_csec=$(clean_rbw_field_value "$(rbw_extract_custom_field clientsecret "$raw_json")")
  f_rt=$(clean_rbw_field_value "$(rbw_extract_custom_field refreshtoken "$raw_json")")
  f_tok=$(clean_rbw_field_value "$(rbw_extract_custom_field token "$raw_json")")

  local n_cid="" n_csec="" n_rt="" n_tok=""
  local notes line raw_key norm_key raw_val cleaned_val
  notes=$(jq -r '([.notes, .data.notes] | map(select(type == "string" and length > 0)) | .[0]) // ""' <<<"$raw_json" 2>/dev/null || true)
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    if [[ $line =~ ^[[:space:]]*[-*]?[[:space:]]*([A-Za-z][A-Za-z0-9_[:space:]-]*)[[:space:]]*[:=][[:space:]]*(.*)$ ]]; then
      raw_key=${BASH_REMATCH[1]}
      raw_val=${BASH_REMATCH[2]}
      norm_key=${raw_key,,}
      norm_key=${norm_key//[-_[:space:]]/}
      case $norm_key in
        clientid)
          cleaned_val=$(clean_rbw_field_value "$raw_val")
          [[ -z $cleaned_val ]] || n_cid=$cleaned_val
          ;;
        clientsecret)
          cleaned_val=$(clean_rbw_field_value "$raw_val")
          [[ -z $cleaned_val ]] || n_csec=$cleaned_val
          ;;
        refreshtoken)
          cleaned_val=$(clean_rbw_field_value "$raw_val")
          [[ -z $cleaned_val ]] || n_rt=$cleaned_val
          ;;
        token)
          cleaned_val=$(clean_rbw_field_value "$raw_val")
          [[ -z $cleaned_val ]] || n_tok=$cleaned_val
          ;;
      esac
    fi
  done <<<"$notes"

  RBW_CLIENT_ID=${f_cid:-$n_cid}
  RBW_CLIENT_SECRET=${f_csec:-$n_csec}

  RBW_TOKEN_JSON=""
  local tok_cand="" normalized_tok=""
  for tok_cand in "$f_rt" "$f_tok" "$n_rt" "$n_tok"; do
    [[ -n $tok_cand ]] || continue
    if normalized_tok=$(normalize_token_input "$tok_cand") && [[ -n $normalized_tok ]]; then
      RBW_TOKEN_JSON=$normalized_tok
      break
    else
      printf "警告: Bitwarden '%s' 内の refresh_token / token の形式が不正なため無視しました。\n" "$RBW_ITEM" >&2
    fi
  done

  RBW_FETCHED=1
  return 0
}

probe_gdrive() {
  rclone about gdrive: --contimeout 10s --timeout 30s --retries 1 --low-level-retries 1
}

write_gdrive_config() {
  local client_id=$1
  local client_secret=$2
  local token_json=${3:-}

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
  else
    rclone config create gdrive drive \
      client_id "$client_id" \
      client_secret "$client_secret" \
      scope drive \
      config_is_local false >/dev/null
  fi
  chmod 600 -- "$RCLONE_CONFIG"
  GDRIVE_CONFIGURED_THIS_RUN=1
}

configure_gdrive() {
  local default_id=${1:-}
  local default_secret=${2:-}
  local default_token_json=${3:-}
  local prefer_default=${4:-0}

  local existing_id="" existing_secret="" dump_json=""
  if [[ -f $RCLONE_CONFIG ]]; then
    dump_json=$(rclone config dump 2>/dev/null || true)
    if [[ -n $dump_json ]]; then
      existing_id=$(jq -r '.gdrive.client_id // empty' <<<"$dump_json" 2>/dev/null || true)
      existing_secret=$(jq -r '.gdrive.client_secret // empty' <<<"$dump_json" 2>/dev/null || true)
    fi
  fi

  if (( prefer_default == 1 )); then
    [[ -n $default_id ]] && existing_id=$default_id
    [[ -n $default_secret ]] && existing_secret=$default_secret
  else
    [[ -n $existing_id ]] || existing_id=$default_id
    [[ -n $existing_secret ]] || existing_secret=$default_secret
  fi

  local client_id="" client_secret="" id_preview=""
  while [[ -z $client_id ]]; do
    if [[ -n $existing_id ]]; then
      id_preview=${existing_id:0:12}
      if (( ${#existing_id} > 12 )); then
        id_preview="${id_preview}..."
      fi
      printf 'Google OAuth client_id [Enter で維持: %s]: ' "$id_preview" >&2
      client_id=$(read_trimmed) || fail 'client_id の入力が中断されました。'
      if [[ -z $client_id ]]; then
        client_id=$existing_id
      fi
    else
      printf 'Google OAuth client_id: ' >&2
      client_id=$(read_trimmed) || fail 'client_id の入力が中断されました。'
      if [[ -z $client_id ]]; then
        printf 'Google OAuth client_id は必須です。\n' >&2
      fi
    fi
  done

  while [[ -z $client_secret ]]; do
    if [[ -n $existing_secret ]]; then
      printf 'Google OAuth client_secret [Enter で既存値を維持]: ' >&2
      client_secret=$(read_trimmed) || fail 'client_secret の入力が中断されました。'
      if [[ -z $client_secret ]]; then
        client_secret=$existing_secret
      fi
    else
      printf 'Google OAuth client_secret: ' >&2
      client_secret=$(read_trimmed) || fail 'client_secret の入力が中断されました。'
      if [[ -z $client_secret ]]; then
        printf 'Google OAuth client_secret は必須です。\n' >&2
      fi
    fi
  done

  local raw_token="" token_json=""
  if [[ -n $default_token_json ]]; then
    token_json=$default_token_json
  else
    while true; do
      printf 'Google OAuth refresh_token（または token JSON。空 Enter でブラウザ OAuth）: ' >&2
      raw_token=$(read_trimmed) || fail 'refresh_token の入力が中断されました。'
      if [[ -z $raw_token ]]; then
        token_json=""
        break
      fi
      if token_json=$(normalize_token_input "$raw_token") && [[ -n $token_json ]]; then
        break
      fi
      printf 'token JSON の形式が不正です（refresh_token または access_token を含む JSON オブジェクトが必要です）。\n' >&2
    done
  fi

  if [[ -n $token_json ]]; then
    write_gdrive_config "$client_id" "$client_secret" "$token_json"
  else
    write_gdrive_config "$client_id" "$client_secret"
    printf '\ngdrive: の対話式 OAuth 認証を開始します。\n' >&2
    printf "実機にブラウザーがない環境では 'Use auto config?' に 'n' と答え、別端末で認証してください。\n" >&2
    if ! rclone config reconnect gdrive:; then
      printf '対話式 OAuth 認証が完了しませんでした。\n' >&2
    fi
    chmod 600 -- "$RCLONE_CONFIG"
  fi
}

ensure_gdrive_remote() {
  GDRIVE_CONFIGURED_THIS_RUN=0
  resolve_rclone_config
  local remotes=""
  remotes=$(rclone listremotes 2>/dev/null || true)
  if ! grep -Fxq 'gdrive:' <<<"$remotes"; then
    local used_rbw=0
    if load_from_rbw 0; then
      used_rbw=1
    fi
    if [[ -n $RBW_CLIENT_ID && -n $RBW_CLIENT_SECRET && -n $RBW_TOKEN_JSON ]]; then
      write_gdrive_config "$RBW_CLIENT_ID" "$RBW_CLIENT_SECRET" "$RBW_TOKEN_JSON"
      printf "Bitwarden (%s) から gdrive: を自動設定しました。\n" "$RBW_ITEM" >&2
    else
      [[ -t 0 ]] || fail "リモート gdrive: が ${RCLONE_CONFIG} に見つかりません。事前に rclone を設定するか、rbw をロック解除状態にするか、対話環境で実行してください。"
      printf '\nリモート gdrive: が未設定です (%s)。\n' "$RCLONE_CONFIG" >&2
      if (( used_rbw == 1 )); then
        printf "Bitwarden (%s) の OAuth 情報に不足があるため、不足項目のみ確認します:\n" "$RBW_ITEM" >&2
      else
        printf "Bitwarden の項目 '%s' などを確認して Google Drive OAuth 情報を入力してください:\n" "$RBW_ITEM" >&2
      fi
      configure_gdrive "$RBW_CLIENT_ID" "$RBW_CLIENT_SECRET" "$RBW_TOKEN_JSON" 1
    fi
  fi

  local action=""
  while ! probe_gdrive; do
    [[ -t 0 ]] || fail 'Google Drive リモート gdrive: への接続に失敗しました。'
    printf '\nGoogle Drive リモート gdrive: への接続に失敗しました。\n' >&2
    while true; do
      printf '選択: [b]Bitwarden (rbw) を同期して再読込, [r]値を手動入力, [o]OAuth ブラウザ再接続, [t]再試行, [q]中止 [b/r/o/t/q]: ' >&2
      action=$(read_trimmed) || fail '操作選択が中断されました。'
      case $action in
        b|B)
          if ! has_rbw; then
            printf 'rbw が利用できないため [r] または [o] を選択してください。\n' >&2
            continue
          fi
          RBW_FETCHED=0
          RBW_DECLINED=0
          if load_from_rbw 1; then
            if [[ -n $RBW_CLIENT_ID && -n $RBW_CLIENT_SECRET && -n $RBW_TOKEN_JSON ]]; then
              write_gdrive_config "$RBW_CLIENT_ID" "$RBW_CLIENT_SECRET" "$RBW_TOKEN_JSON"
              printf "Bitwarden (%s) から gdrive: を再設定しました。\n" "$RBW_ITEM" >&2
              break
            elif [[ -n $RBW_CLIENT_ID || -n $RBW_CLIENT_SECRET || -n $RBW_TOKEN_JSON ]]; then
              printf "Bitwarden (%s) の一部項目のみ取得できたため、不足分を確認します:\n" "$RBW_ITEM" >&2
              configure_gdrive "$RBW_CLIENT_ID" "$RBW_CLIENT_SECRET" "$RBW_TOKEN_JSON" 1
              break
            else
              printf "Bitwarden (%s) に OAuth 項目（client_id / client_secret / refresh_token）が見つかりませんでした。\n" "$RBW_ITEM" >&2
            fi
          fi
          ;;
        r|R)
          configure_gdrive "$RBW_CLIENT_ID" "$RBW_CLIENT_SECRET" "" 0
          break
          ;;
        o|O)
          printf '\ngdrive: の対話式 OAuth 再接続を開始します。\n' >&2
          printf "実機にブラウザーがない環境では 'Use auto config?' に 'n' と答え、別端末で認証してください。\n" >&2
          if ! rclone config reconnect gdrive:; then
            printf '対話式 OAuth 再接続が完了しませんでした。\n' >&2
          fi
          chmod 600 -- "$RCLONE_CONFIG" 2>/dev/null || true
          GDRIVE_CONFIGURED_THIS_RUN=1
          break
          ;;
        t|T)
          break
          ;;
        q|Q)
          fail '中止しました。'
          ;;
        *)
          printf 'b, r, o, t, q のいずれかを入力してください。\n' >&2
          ;;
      esac
    done
  done
}

need_rbw_upfront() {
  [[ ${RESTORE_NO_RBW:-0} != 1 ]] || return 1
  resolve_rclone_config
  local have_gdrive=0 have_pw=0
  if [[ -f $RCLONE_CONFIG ]] && grep -Eiq '^[[:space:]]*\[gdrive\][[:space:]]*$' -- "$RCLONE_CONFIG"; then
    have_gdrive=1
  fi
  if [[ -v RESTIC_PASSWORD || -n ${RESTIC_PASSWORD_FILE:-} || -n ${RESTIC_PASSWORD_COMMAND:-} ]]; then
    have_pw=1
  fi
  if (( have_gdrive == 0 || have_pw == 0 )); then
    return 0
  fi
  return 1
}

ensure_tools() {
  local pinentry_pkg=""
  if [[ -n ${DISPLAY:-} || -n ${WAYLAND_DISPLAY:-} ]]; then
    pinentry_pkg=pinentry-qt
  else
    pinentry_pkg=pinentry-curses
  fi

  local need_core=0 tool
  for tool in rclone restic jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      need_core=1
      break
    fi
  done

  local need_python=0
  if ! command -v python3 >/dev/null 2>&1; then
    need_python=1
  fi

  local need_rbw=0 need_pinentry=0
  if need_rbw_upfront; then
    if ! command -v rbw >/dev/null 2>&1; then
      need_rbw=1
    fi
    if ! configured_pinentry_works && ! desired_pinentry_cmd >/dev/null 2>&1; then
      if ! { command -v rbw >/dev/null 2>&1 && rbw unlocked >/dev/null 2>&1; }; then
        need_pinentry=1
      fi
    fi
  fi

  local run_nix=0
  if (( need_core == 1 )); then
    command -v nix >/dev/null 2>&1 || fail '不足しているツール（restic / rclone / jq）の取得に nix コマンドが必要です。'
    run_nix=1
  elif (( need_python == 1 || need_rbw == 1 || need_pinentry == 1 )) && command -v nix >/dev/null 2>&1; then
    run_nix=1
  fi

  if (( run_nix == 1 )); then
    local script
    script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"
    local -a nix_pkgs=(nixpkgs#restic nixpkgs#rclone nixpkgs#jq)
    local -a verify_cmds=(restic rclone jq)
    if (( need_python == 1 )) || ! command -v python3 >/dev/null 2>&1; then
      nix_pkgs+=(nixpkgs#python3)
      verify_cmds+=(python3)
    fi
    if [[ ${RESTORE_NO_RBW:-0} != 1 ]] && { (( need_rbw == 1 )) || ! command -v rbw >/dev/null 2>&1; }; then
      nix_pkgs+=(nixpkgs#rbw)
      verify_cmds+=(rbw)
    fi
    if [[ ${RESTORE_NO_RBW:-0} != 1 ]] && { (( need_pinentry == 1 )) || { ! configured_pinentry_works && ! desired_pinentry_cmd >/dev/null 2>&1; }; }; then
      nix_pkgs+=("nixpkgs#${pinentry_pkg}")
      verify_cmds+=("$pinentry_pkg")
    fi

    local verify_list="${verify_cmds[*]}"
    printf 'nix shell で不足ツールを取得しています (%s)...\n' "$verify_list"
    # 内側の bash が位置引数とツール名を展開する。
    # shellcheck disable=SC2016
    exec nix --extra-experimental-features 'nix-command flakes' shell \
      "${nix_pkgs[@]}" \
      --command bash -c '
        IFS=" " read -r -a _tools <<<"$1"
        for tool in "${_tools[@]}"; do
          command -v "$tool" >/dev/null 2>&1 || exit 1
        done
        shift
        exec bash "$@"
      ' restore-tools "$verify_list" "$script" "$@"
  fi
}

available_bytes_for() {
  local val=""
  val=$(df --output=avail -B1 -- "$1" 2>/dev/null | awk 'NR==2 {print $1}') || return 1
  [[ $val =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$val"
}

main() {
  set -euo pipefail
  umask 077
  if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    usage
    return 0
  fi
  (( $# <= 1 )) || fail '引数が多すぎます。--help を確認してください。'
  local explicit_target=${1:-}
  local root_prefix=${RESTORE_ROOT:-/}
  root_prefix=${root_prefix%/}
  local target_home="${root_prefix}/home/mitac"
  local stage_parent_override=${RESTORE_STAGE_PARENT:-}
  local default_stage_parent=${_RESTORE_DEFAULT_STAGE_PARENT:-/var/tmp}
  local target="" parent="" stage_prefix="restore-mitac"

  if [[ -n $explicit_target ]]; then
    target=$explicit_target
    [[ $target == /* ]] || fail '展開先パスは絶対パスで指定してください（--help を参照）。'
    [[ ! -e $target && ! -L $target ]] || fail "指定された展開先は既に存在します。新しいディレクトリを指定してください: $target"
    parent=$(dirname -- "$target")
    [[ -d $parent && -w $parent ]] || fail "親ディレクトリに書き込み権限がありません: $parent"
  elif [[ -n $stage_parent_override ]]; then
    parent=$stage_parent_override
    [[ -d $parent && -w $parent ]] || fail "一時ステージ用の親ディレクトリに書き込み権限がありません: $parent"
  else
    [[ ( -d $default_stage_parent && -w $default_stage_parent ) || ( -d $target_home && -w $target_home ) ]] ||
      fail "一時ステージ用の親ディレクトリ（${default_stage_parent} または ${target_home}）に書き込み権限がありません。"
  fi

  check_platform
  ensure_tools "$@"
  ensure_gdrive_remote

  export RESTIC_REPOSITORY=rclone:gdrive:restic/mitac-home

  # 先にスナップショット ID を固定してから必要容量・復元を行う。
  local snapshot_id="" snapshots_json="" stats required_bytes available_bytes
  if [[ ! -v RESTIC_PASSWORD && -z ${RESTIC_PASSWORD_FILE:-} && -z ${RESTIC_PASSWORD_COMMAND:-} ]]; then
    local pw_resolved=0 rbw_attempted=0
    if has_rbw && (( RBW_DECLINED == 0 )); then
      if load_from_rbw 0; then
        rbw_attempted=1
        if [[ -n $RBW_PASSWORD ]]; then
          export RESTIC_PASSWORD=$RBW_PASSWORD
          printf "Bitwarden (%s) から取得した暗号化パスワードでリポジトリを確認しています...\n" "$RBW_ITEM" >&2
          if snapshots_json=$(restic snapshots --json latest); then
            pw_resolved=1
          else
            unset RESTIC_PASSWORD
            printf "Bitwarden (%s) のパスワードでは restic リポジトリを開けませんでした。\n" "$RBW_ITEM" >&2
          fi
        else
          printf "Bitwarden (%s) のパスワード欄が空です。\n" "$RBW_ITEM" >&2
        fi
      fi
    fi

    if (( pw_resolved == 0 )); then
      [[ -t 0 ]] || fail 'RESTIC_PASSWORD / RESTIC_PASSWORD_FILE / RESTIC_PASSWORD_COMMAND を設定するか、rbw をロック解除状態にするか、対話環境で実行してください。'

      local use_manual_pw=1 pw_action=""
      if (( rbw_attempted == 1 )) && has_rbw; then
        use_manual_pw=0
        while (( use_manual_pw == 0 && pw_resolved == 0 )); do
          printf '選択: [b]Bitwarden (rbw) を同期して再試行, [m]パスワードを手動入力, [q]中止 [b/m/q]: ' >&2
          pw_action=$(read_trimmed) || fail '操作選択が中断されました。'
          case $pw_action in
            b|B)
              RBW_FETCHED=0
              RBW_DECLINED=0
              if load_from_rbw 1; then
                if [[ -n $RBW_PASSWORD ]]; then
                  export RESTIC_PASSWORD=$RBW_PASSWORD
                  printf "Bitwarden (%s) から再取得したパスワードでリポジトリを確認しています...\n" "$RBW_ITEM" >&2
                  if snapshots_json=$(restic snapshots --json latest); then
                    pw_resolved=1
                    break
                  fi
                  unset RESTIC_PASSWORD
                  printf "Bitwarden (%s) のパスワードでは restic リポジトリを開けませんでした。\n" "$RBW_ITEM" >&2
                else
                  printf "Bitwarden (%s) のパスワード欄が空です。\n" "$RBW_ITEM" >&2
                fi
              fi
              ;;
            m|M)
              use_manual_pw=1
              ;;
            q|Q)
              fail '中止しました。'
              ;;
            *)
              printf 'b, m, q のいずれかを入力してください。\n' >&2
              ;;
          esac
        done
      fi

      local pw="" retry=""
      while (( pw_resolved == 0 )); do
        printf "restic 暗号化パスワードを入力してください（Bitwarden 項目 '%s'、入力は非表示）: " "$RBW_ITEM" >&2
        IFS= read -rs pw || fail '暗号化パスワードの入力が中断されました。'
        printf '\n' >&2
        if [[ -z $pw ]]; then
          printf 'パスワードは空にできません。\n' >&2
          continue
        fi
        export RESTIC_PASSWORD=$pw
        if snapshots_json=$(restic snapshots --json latest); then
          pw_resolved=1
          break
        fi
        printf '入力されたパスワードで restic リポジトリを開けませんでした。\n' >&2
        printf 'パスワードを再入力しますか？ [Y/n] ' >&2
        retry=$(read_trimmed) || fail '操作選択が中断されました。'
        case $retry in
          ''|y|Y|yes|YES) continue ;;
          *)
            unset RESTIC_PASSWORD
            fail '中止しました。'
            ;;
        esac
      done
    fi
  else
    snapshots_json=$(restic snapshots --json latest)
  fi
  snapshot_id=$(jq -er '.[0].id // empty' <<<"$snapshots_json") || fail '復元対象のスナップショットが見つかりませんでした。'
  [[ $snapshot_id =~ ^[0-9a-f]{64}$ ]] || fail '復元対象のスナップショットが見つかりませんでした。'
  restic snapshots "$snapshot_id"
  stats=$(restic stats "$snapshot_id" --mode restore-size --json)
  required_bytes=$(jq -er '.total_size | select(type == "number" and . >= 0) | floor' <<<"$stats")
  printf '復元に必要なサイズ: %s バイト\n' "$required_bytes"

  if [[ -z $explicit_target && -z $stage_parent_override ]]; then
    local vartmp_ok=0 home_ok=0 dev_vartmp="" dev_home="" avail_vartmp=0 avail_home=0
    if [[ -d $default_stage_parent && -w $default_stage_parent ]]; then
      vartmp_ok=1
      dev_vartmp=$(stat -Lc '%d' -- "$default_stage_parent" 2>/dev/null || true)
      avail_vartmp=$(available_bytes_for "$default_stage_parent" || printf '0')
    fi
    if [[ -d $target_home && -w $target_home ]]; then
      home_ok=1
      dev_home=$(stat -Lc '%d' -- "$target_home" 2>/dev/null || true)
      avail_home=$(available_bytes_for "$target_home" || printf '0')
    fi

    if (( home_ok == 1 && vartmp_ok == 1 )); then
      if [[ -n $dev_home && -n $dev_vartmp && $dev_home != "$dev_vartmp" ]]; then
        if (( avail_home >= required_bytes )); then
          parent=$target_home
          stage_prefix=.restore-mitac
          printf '一時展開先に %s を選択しました（%s とは別ファイルシステム／サブボリュームのため同一 FS 上で高速反映します）。\n' "$target_home" "$default_stage_parent" >&2
        elif (( avail_vartmp >= required_bytes )); then
          parent=$default_stage_parent
          stage_prefix=restore-mitac
          printf '注意: %s の空き容量が不足しているため %s を一時展開先に使います（反映時のコピーに時間がかかります）。\n' "$target_home" "$default_stage_parent" >&2
        else
          parent=$target_home
          stage_prefix=.restore-mitac
        fi
      elif (( avail_vartmp >= required_bytes )); then
        parent=$default_stage_parent
        stage_prefix=restore-mitac
      elif (( avail_home >= required_bytes )); then
        parent=$target_home
        stage_prefix=.restore-mitac
      else
        parent=$default_stage_parent
        stage_prefix=restore-mitac
      fi
    elif (( home_ok == 1 )); then
      parent=$target_home
      stage_prefix=.restore-mitac
      printf '一時展開先に %s を選択しました（%s が利用できないためホーム内で展開・反映します）。\n' "$target_home" "$default_stage_parent" >&2
    else
      parent=$default_stage_parent
      stage_prefix=restore-mitac
    fi
  fi

  df -h -- "$parent"
  available_bytes=$(available_bytes_for "$parent") || fail "空き容量を取得できませんでした: $parent"
  (( available_bytes >= required_bytes )) || fail '空き容量が不足しています。別のディスク上の新しい展開先ディレクトリを指定してください。'

  if [[ -n $explicit_target ]]; then
    # 指定ディレクトリへ展開・検証のみ行い、/home や /etc は変更しない。
    mkdir -m 700 -- "$target"
    printf '展開先 (%s) へ検証付きで復元しています...\n' "$target" >&2
    restic restore "$snapshot_id" --target "$target" --verify
    printf '%s\n' "$snapshot_id" > "$target/.restored-snapshot-id"
    printf '\n復元と検証が完了しました。\n'
    printf '展開先: %s\n' "$target"
    printf 'ホーム: %s/home/mitac\n' "$target"
    printf 'システム状態: %s/run/restic-backups-home/system\n' "$target"
    printf 'フォント: %s/home/mitac/Documents/hiragino-otf\n' "$target"
    return 0
  fi

  local stage_dir
  stage_dir=$(mktemp -d "${parent%/}/${stage_prefix}-XXXXXXXX")
  chmod 700 -- "$stage_dir"
  printf '一時展開先 (%s) へ検証付きで展開しています...\n' "$stage_dir" >&2
  restic restore "$snapshot_id" --target "$stage_dir" --verify

  local preserved_rclone=""
  if (( GDRIVE_CONFIGURED_THIS_RUN == 1 )) && [[ -f $RCLONE_CONFIG ]]; then
    preserved_rclone="${stage_dir}/.preserved-rclone.conf"
    cp -p -- "$RCLONE_CONFIG" "$preserved_rclone"
    chmod 600 -- "$preserved_rclone"
  fi

  if [[ -d "${stage_dir}/home/mitac" ]]; then
    printf '展開・検証が完了しました。%s へ反映しています...\n' "$target_home" >&2
    move_tree "${stage_dir}/home/mitac" "$target_home" "$stage_dir"
  fi

  local restore_home_mode=""
  if [[ ( -n $preserved_rclone || $stage_dir == "$target_home"/* ) && -d $target_home && ! -w $target_home ]]; then
    restore_home_mode=$(stat -c '%a' -- "$target_home")
    chmod u+rwx -- "$target_home"
  fi

  if [[ -n $preserved_rclone && -f $preserved_rclone ]]; then
    mkdir -p -- "$(dirname -- "$RCLONE_CONFIG")"
    cp -f --remove-destination -- "$preserved_rclone" "$RCLONE_CONFIG"
    chmod 600 -- "$RCLONE_CONFIG"
    rm -f -- "$preserved_rclone"
  fi

  restore_system_state "${stage_dir}/run/restic-backups-home/system" "$root_prefix"
  rm -rf -- "$stage_dir"
  if [[ -n $restore_home_mode ]]; then
    chmod "$restore_home_mode" -- "$target_home"
  fi

  printf '\n復元と検証が完了しました。\n'
  printf 'スナップショット: %s\n' "$snapshot_id"
  printf 'ホーム: %s\n' "$target_home"
  printf 'システム状態: %s/etc/NetworkManager/system-connections, %s/var/lib/{bluetooth,cloudflare-warp,tailscale}\n' "$root_prefix" "$root_prefix"
  printf 'フォント（バックアップ時）: %s/Documents/hiragino-otf\n' "$target_home"
  printf '%s/MySettings から NixOS を再ビルドする際、Documents/hiragino-otf がある場合は --impure を付けてください。\n' "$target_home"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
