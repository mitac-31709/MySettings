#!/usr/bin/env bash
# OS ビルド前（初期日本語 LXQt 等）または再構築後に /home バックアップを復元するスクリプト。

usage() {
  cat <<'EOF'
使い方: ./scripts/restore-on-nixos.sh [OPTIONS] [EXTRACT_DIR]

対象 NixOS マシン上でユーザー mitac として実行します（sudo は付けない）。
不足ツール（restic / rclone / jq / python3 / rbw / pinentry）は nix shell で自動取得します。

オプション:
  --from HOST    別のホスト用リポジトリ（rclone:gdrive:restic/<HOST>-home）から復元
                 例: --from vaio --new-device / --from chromebook --new-device
  --repo REPO    restic リポジトリ URI を明示指定（--from と併用不可）
  --new-device   別端末や初期化後のクリーン構築向けに衝突する端末 ID・P2P 鍵・
                 VPN/BT 状態・トークン系認証状態を除外/初期化して復元する
                 （Wi-Fi パスワードの NIC 名/MAC 縛りも自動解除、既存の ~/MySettings
                 チェックアウト・rbw・rclone.conf は保持）
  --agenix-only  restic 復元を行わず、Bitwarden (rbw) の 'agenix-master-key'
                 から ${RESTORE_ROOT:-/}/etc/agenix/master.key (0400 root:root) のみ導入
  -h, --help     このヘルプを表示

復元元リポジトリの既定値:
  1. --repo / --from 指定時はそのリポジトリ
  2. 環境変数 RESTIC_REPOSITORY（設定済みの場合）
  3. RESTORE_HOST または現在ホスト名に基づく rclone:gdrive:restic/<host>-home
     （未設定・nixos・localhost の場合は rclone:gdrive:restic/mitac-home）

既定（EXTRACT_DIR なし）:
  一時領域（/home/mitac と同一ファイルシステムを優先: 同一 FS なら /var/tmp、
  別パーティション／Btrfs 別サブボリューム時は /home/mitac 内の隠し領域）で
  restic --verify による検証を完了させた後、元の位置へ上書き復元します:
    - ホーム: /home/mitac（既存ファイルを上書き。今回の実行で新規取得／再認証
      した rclone.conf、および --new-device 時は既存の rclone.conf・rbw・
      ~/MySettings も保持）
    - システム状態（必要時のみ sudo）: /etc/NetworkManager/system-connections,
      /var/lib/bluetooth, /var/lib/cloudflare-warp, /var/lib/tailscale
      （--new-device 時は bluetooth / cloudflare-warp / tailscale を除外）
EXTRACT_DIR 指定時（未作成の絶対パス）:
  /home や /etc には触れず、EXTRACT_DIR 配下への展開と検証のみを行います
  （--new-device 併用時は EXTRACT_DIR 内のステージ領域に同じ初期化処理を適用）。

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
環境変数 RBW_ITEM / RBW_EMAIL / RBW_BASE_URL / RESTORE_HOST も利用できます。
EOF
}

GDRIVE_CONFIGURED_THIS_RUN=0
NEW_DEVICE=${NEW_DEVICE:-0}
AGENIX_ONLY=${AGENIX_ONLY:-0}
AGENIX_KEY_INSTALLED=0
FROM_HOST=${FROM_HOST:-}
EXPLICIT_REPO=${EXPLICIT_REPO:-}
EXPLICIT_TARGET=""
HELP_REQUESTED=0
RBW_ITEM=${RBW_ITEM:-restic-home}
RBW_AGENIX_ITEM=${RBW_AGENIX_ITEM:-agenix-master-key}
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

extract_agenix_master_key_from_rbw() {
  local out_file=$1 raw_json="" candidate="" notes="" line=""
  raw_json=$(rbw get --raw "$RBW_AGENIX_ITEM" 2>/dev/null) || return 1
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$raw_json" || return 1

  candidate=$(jq -r '.data.password // empty' <<<"$raw_json" 2>/dev/null || true)
  candidate=$(trim_ws "$candidate")
  if [[ -n $candidate ]] && { [[ $candidate == AGE-SECRET-KEY-1* ]] || [[ $candidate == *"BEGIN OPENSSH PRIVATE KEY"* ]]; }; then
    printf '%s\n' "$candidate" >"$out_file"
    chmod 600 -- "$out_file"
    return 0
  fi

  notes=$(jq -r '([.notes, .data.notes] | map(select(type == "string" and length > 0)) | .[0]) // ""' <<<"$raw_json" 2>/dev/null || true)
  if [[ $notes == *"BEGIN OPENSSH PRIVATE KEY"* ]]; then
    local in_block=0 found_end=0 block_buf=""
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line%$'\r'}
      if (( in_block == 0 )); then
        if [[ $line == "-----BEGIN OPENSSH PRIVATE KEY-----" ]]; then
          in_block=1
          block_buf="${line}"$'\n'
        fi
      else
        block_buf+="${line}"$'\n'
        if [[ $line == "-----END OPENSSH PRIVATE KEY-----" ]]; then
          found_end=1
          break
        fi
      fi
    done <<<"$notes"
    if (( found_end == 1 )); then
      printf '%s' "$block_buf" >"$out_file"
      chmod 600 -- "$out_file"
      return 0
    fi
  fi
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    line=$(trim_ws "$line")
    if [[ $line == AGE-SECRET-KEY-1* ]]; then
      printf '%s\n' "$line" >"$out_file"
      chmod 600 -- "$out_file"
      return 0
    fi
  done <<<"$notes"

  return 1
}

install_agenix_master_key() {
  local src_key=$1 root_prefix=${2%/}
  local dest_dir="${root_prefix}/etc/agenix"
  local dest_key="${dest_dir}/master.key"
  run_sudo mkdir -p -- "$dest_dir"
  run_sudo chmod 700 -- "$dest_dir"
  run_sudo chown root:root -- "$dest_dir"
  run_sudo cp -f --remove-destination -- "$src_key" "$dest_key"
  run_sudo chown root:root -- "$dest_key"
  run_sudo chmod 400 -- "$dest_key"
  AGENIX_KEY_INSTALLED=1
}

maybe_bootstrap_agenix_from_rbw() {
  local root_prefix=${1%/} required=${2:-0}
  [[ ${RESTORE_SKIP_AGENIX:-0} != 1 ]] || return 0
  if ! has_rbw; then
    (( required == 0 )) && return 0
    fail 'rbw が利用できないため agenix マスター鍵を導入できません。'
  fi

  if (( required == 1 )); then
    ensure_rbw_unlocked 1 || fail 'Bitwarden (rbw) のロック解除に失敗しました。'
    rbw sync >/dev/null 2>&1 || true
  else
    rbw unlocked >/dev/null 2>&1 || return 0
  fi

  local tmp_key
  tmp_key=$(mktemp "${TMPDIR:-/tmp}/restore-agenix-key-XXXXXXXX")
  chmod 600 -- "$tmp_key"
  if extract_agenix_master_key_from_rbw "$tmp_key"; then
    install_agenix_master_key "$tmp_key" "$root_prefix"
    rm -f -- "$tmp_key"
    printf "agenix マスター復号鍵 (%s) を %s/etc/agenix/master.key へ配置しました。\n" "$RBW_AGENIX_ITEM" "$root_prefix" >&2
    return 0
  fi
  rm -f -- "$tmp_key"
  if (( required == 1 )); then
    fail "Bitwarden に項目 '$RBW_AGENIX_ITEM' が見つからないか、age / SSH 秘密鍵形式ではありません。"
  fi
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
  (( AGENIX_ONLY == 0 )) || return 0
  resolve_rclone_config
  local resolved_repo=""
  resolved_repo=$(resolve_repository "$FROM_HOST" "$EXPLICIT_REPO")
  local have_gdrive=0 have_pw=0
  if [[ $resolved_repo != rclone:gdrive:* ]] ||
     { [[ -f $RCLONE_CONFIG ]] && grep -Eiq '^[[:space:]]*\[gdrive\][[:space:]]*$' -- "$RCLONE_CONFIG"; }; then
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
  local -a core_tools=(rclone restic jq)
  if (( AGENIX_ONLY == 1 )); then
    core_tools=(jq)
  fi
  for tool in "${core_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      need_core=1
      break
    fi
  done

  local need_python=0
  if (( AGENIX_ONLY == 0 )); then
    if ! command -v python3 >/dev/null 2>&1; then
      need_python=1
    elif (( NEW_DEVICE == 1 )) && ! python3 -c 'import sqlite3' >/dev/null 2>&1; then
      need_python=1
    fi
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
    local -a nix_pkgs=(nixpkgs#jq)
    local -a verify_cmds=(jq)
    if (( AGENIX_ONLY == 0 )); then
      nix_pkgs=(nixpkgs#restic nixpkgs#rclone nixpkgs#jq)
      verify_cmds=(restic rclone jq)
    fi
    if (( AGENIX_ONLY == 0 )) && { (( need_python == 1 )) || ! command -v python3 >/dev/null 2>&1 ||
       { (( NEW_DEVICE == 1 )) && ! python3 -c 'import sqlite3' >/dev/null 2>&1; }; }; then
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

validate_host_name() {
  local host=$1
  [[ -n $host && $host != . && $host != .. && $host =~ ^[A-Za-z0-9._-]+$ ]] ||
    fail "--from のホスト名が不正です: '$host'（英数字・._- のみ使用可）"
}

parse_args() {
  NEW_DEVICE=0
  AGENIX_ONLY=0
  FROM_HOST=""
  EXPLICIT_REPO=""
  EXPLICIT_TARGET=""
  HELP_REQUESTED=0

  local -a positionals=()
  while (( $# > 0 )); do
    case $1 in
      -h|--help)
        HELP_REQUESTED=1
        return 0
        ;;
      --new-device)
        NEW_DEVICE=1
        shift
        ;;
      --agenix-only)
        AGENIX_ONLY=1
        shift
        ;;
      --from)
        (( $# >= 2 )) || fail '--from にはホスト名を指定してください。'
        FROM_HOST=$(trim_ws "$2")
        validate_host_name "$FROM_HOST"
        shift 2
        ;;
      --from=*)
        FROM_HOST=$(trim_ws "${1#--from=}")
        validate_host_name "$FROM_HOST"
        shift
        ;;
      --repo)
        (( $# >= 2 )) || fail '--repo にはリポジトリ URI を指定してください。'
        EXPLICIT_REPO=$(trim_ws "$2")
        [[ -n $EXPLICIT_REPO ]] || fail '--repo の値は空にできません。'
        shift 2
        ;;
      --repo=*)
        EXPLICIT_REPO=$(trim_ws "${1#--repo=}")
        [[ -n $EXPLICIT_REPO ]] || fail '--repo の値は空にできません。'
        shift
        ;;
      --)
        shift
        positionals+=("$@")
        break
        ;;
      -*)
        fail "不明なオプションです: $1（--help を確認してください）。"
        ;;
      *)
        positionals+=("$1")
        shift
        ;;
    esac
  done

  if [[ -n $FROM_HOST && -n $EXPLICIT_REPO ]]; then
    fail '--from と --repo は同時に指定できません。'
  fi
  (( ${#positionals[@]} <= 1 )) || fail '引数が多すぎます。--help を確認してください。'
  EXPLICIT_TARGET=${positionals[0]:-}
  if (( AGENIX_ONLY == 1 )) && [[ -n $EXPLICIT_TARGET ]]; then
    fail '--agenix-only と EXTRACT_DIR は同時に指定できません。'
  fi
}

resolve_repository() {
  local from_host=${1:-} explicit_repo=${2:-}
  if [[ -n $explicit_repo ]]; then
    printf '%s' "$explicit_repo"
    return 0
  fi
  if [[ -n $from_host ]]; then
    printf 'rclone:gdrive:restic/%s-home' "$from_host"
    return 0
  fi
  if [[ -n ${RESTIC_REPOSITORY:-} ]]; then
    printf '%s' "$RESTIC_REPOSITORY"
    return 0
  fi

  local host=${RESTORE_HOST:-}
  if [[ -z $host ]]; then
    host=$(uname -n 2>/dev/null || true)
    host=${host%%.*}
  fi
  host=$(trim_ws "$host")
  host=${host,,}
  if [[ -z $host || $host == nixos || $host == localhost || ! $host =~ ^[a-z0-9._-]+$ ]]; then
    printf 'rclone:gdrive:restic/mitac-home'
  else
    printf 'rclone:gdrive:restic/%s-home' "$host"
  fi
}

remove_staged_path() {
  local p=$1
  [[ -e $p || -L $p ]] || return 0
  if ! rm -rf -- "$p" 2>/dev/null; then
    chmod -R u+rwX -- "$p" 2>/dev/null || true
    rm -rf -- "$p"
  fi
}

purge_chromium_auth_artifacts() {
  local dir=$1
  [[ -d $dir ]] || return 0
  local -a auth_items=(
    Cookies
    Cookies-journal
    "Extension Cookies"
    "Extension Cookies-journal"
    "Safe Browsing Cookies"
    "Safe Browsing Cookies-journal"
    "Local Storage"
    "Session Storage"
    WebStorage
    "Web Storage"
    Partitions
    SharedStorage
    SharedStorage-wal
    DIPS
    DIPS-wal
    "Trust Tokens"
    "Trust Tokens-journal"
    "Network Persistent State"
    TransportSecurity
    "GCM Store"
    "Sync Data"
    "Login Data"
    "Login Data-journal"
  )
  local item
  for item in "${auth_items[@]}"; do
    remove_staged_path "${dir}/${item}"
  done
}

# Older snapshots excluded Default/Extensions while keeping Preferences +
# extensions_crx_cache. Rebuild missing trees from the CRX cache so extensions
# are not left pointing at absent paths after restore.
repair_vivaldi_extensions_from_crx() {
  local stage_home=${1%/}
  local vivaldi_dir="${stage_home}/.config/vivaldi"
  local cache="${vivaldi_dir}/extensions_crx_cache"
  local pref="${vivaldi_dir}/Default/Preferences"
  local ext_root="${vivaldi_dir}/Default/Extensions"
  local meta="${cache}/metadata.json"

  [[ -f $pref && -f $meta ]] || return 0

  printf 'Vivaldi: extensions_crx_cache から Default/Extensions を補完しています...\n' >&2
  python3 - "$pref" "$cache" "$ext_root" "$meta" <<'PY'
import io, json, shutil, sys, zipfile
from pathlib import Path

pref_path, cache, ext_root, meta_path = map(Path, sys.argv[1:5])
pref = json.loads(pref_path.read_text(encoding="utf-8"))
settings = pref.setdefault("extensions", {}).setdefault("settings", {})
hashes = json.loads(meta_path.read_text(encoding="utf-8")).get("hashes") or {}
restored = 0

for digest, info in sorted(hashes.items()):
    if not isinstance(info, dict):
        continue
    eid = info.get("appid")
    if not eid:
        continue
    crx = cache / digest
    if not crx.is_file():
        continue
    ent = settings.get(eid) if isinstance(settings.get(eid), dict) else {}
    rel = ent.get("path") if isinstance(ent, dict) else None
    if not isinstance(rel, str) or not rel or rel.startswith("/"):
        data = crx.read_bytes()
        idx = data.find(b"PK\x03\x04")
        if idx < 0:
            continue
        man = json.loads(zipfile.ZipFile(io.BytesIO(data[idx:])).read("manifest.json"))
        rel = f"{eid}/{man.get('version', '0')}_0"
        settings.setdefault(eid, {})
        if isinstance(settings[eid], dict):
            settings[eid]["path"] = rel
    dest = ext_root / rel
    if dest.is_dir() and (dest / "manifest.json").is_file():
        continue
    data = crx.read_bytes()
    idx = data.find(b"PK\x03\x04")
    if idx < 0:
        continue
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data[idx:])) as z:
        z.extractall(dest)
    restored += 1
    print(f"  {eid} → {rel}", flush=True)

if restored:
    pref_path.write_text(
        json.dumps(pref, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
print(f"Vivaldi extensions repaired from CRX cache: {restored}", flush=True)
PY
}

scrub_new_device_structured() {
  local stage_sys=$1 stage_home=$2
  python3 - "$stage_sys" "$stage_home" <<'PYEOF'
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import sys
import tempfile

stage_sys = Path(sys.argv[1])
stage_home = Path(sys.argv[2])


def ensure_writable_mode(path: Path) -> int:
    st_mode = stat.S_IMODE(path.stat().st_mode)
    if not (st_mode & stat.S_IWUSR):
        os.chmod(path, st_mode | stat.S_IWUSR)
    return st_mode


def write_atomic_text(path: Path, text: str, mode: int) -> None:
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.scrub-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.chmod(tmp_name, mode)
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def scrub_nm_connections(nm_dir: Path) -> None:
    if not nm_dir.is_dir():
        return
    pattern = re.compile(r"^\s*(?:interface-name|mac-address)\s*=")
    for entry in nm_dir.iterdir():
        if not entry.is_file() or entry.is_symlink():
            continue
        mode = ensure_writable_mode(entry)
        try:
            raw = entry.read_text(encoding="utf-8", errors="surrogateescape")
        except OSError:
            continue
        lines = raw.splitlines(keepends=True)
        filtered = [ln for ln in lines if not pattern.match(ln)]
        if len(filtered) != len(lines):
            write_atomic_text(entry, "".join(filtered), mode or 0o600)


def scrub_json_file(path: Path, mutator) -> None:
    if not path.is_file() or path.is_symlink():
        return
    mode = ensure_writable_mode(path)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"警告: JSON の解析に失敗したためスキップします ({path}): {exc}", file=sys.stderr)
        return
    if not isinstance(data, dict):
        return
    if mutator(data):
        write_atomic_text(
            path,
            json.dumps(data, ensure_ascii=False, separators=(",", ":")),
            mode,
        )


def scrub_vivaldi_local_state(data: dict) -> bool:
    changed = False
    for key in ("user_experience_metrics", "signin"):
        if key in data:
            del data[key]
            changed = True
    viv = data.get("vivaldi")
    if isinstance(viv, dict):
        for key in ("unique_user_id", "CrashReportLastUuidSeen", "stats"):
            if key in viv:
                del viv[key]
                changed = True
    return changed


def scrub_vivaldi_preferences(data: dict) -> bool:
    changed = False
    for key in (
        "sync",
        "invalidation",
        "gcm",
        "gaia_cookie",
        "account_info",
        "account_values",
        "signin",
        "google",
        "enterprise_profile_guid",
        "account_tracker_service_last_update",
    ):
        if key in data:
            del data[key]
            changed = True
    viv = data.get("vivaldi")
    if isinstance(viv, dict) and "vivaldi_account" in viv:
        del viv["vivaldi_account"]
        changed = True
    return changed


def scrub_cursor_storage_json(data: dict) -> bool:
    keys = [k for k in list(data.keys()) if k.startswith("telemetry.")]
    for k in keys:
        del data[k]
    return bool(keys)


def scrub_cursor_state_db(db_path: Path) -> None:
    if not db_path.is_file() or db_path.is_symlink():
        return
    ensure_writable_mode(db_path)
    for suffix in ("-wal", "-shm"):
        side = Path(str(db_path) + suffix)
        if side.is_file() and not side.is_symlink():
            ensure_writable_mode(side)
    con = sqlite3.connect(str(db_path))
    try:
        cur = con.cursor()
        row = cur.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='ItemTable'"
        ).fetchone()
        if not row:
            return
        cur.execute(
            """
            DELETE FROM ItemTable
            WHERE key LIKE 'cursorAuth/%'
               OR key LIKE 'secret://%'
               OR key LIKE 'mcpOAuth.%'
               OR key LIKE 'remoteAgentHost.%'
               OR key LIKE 'cloudAgentRepository.%'
               OR key LIKE 'agentData.cacheStorage.%'
               OR key LIKE 'glass.cloudRepo%'
               OR key LIKE 'cursor/glass.%'
               OR key LIKE 'cursor/localLastActivity%'
               OR key IN ('adminSettings.cached', 'adminSettings.cachedAuthId', 'glass.lastSignedInAuthId')
            """
        )
        con.commit()
        try:
            cur.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        except sqlite3.DatabaseError:
            pass
    finally:
        con.close()


def count_unquoted_braces(line: str) -> tuple[int, int]:
    opens = 0
    closes = 0
    in_quotes = False
    escaped = False
    for ch in line:
        if escaped:
            escaped = False
            continue
        if ch == "\\" and in_quotes:
            escaped = True
            continue
        if ch == '"':
            in_quotes = not in_quotes
        elif not in_quotes:
            if ch == "{":
                opens += 1
            elif ch == "}":
                closes += 1
    return opens, closes


def scrub_steam_config_vdf(vdf_path: Path) -> None:
    if not vdf_path.is_file() or vdf_path.is_symlink():
        return
    mode = ensure_writable_mode(vdf_path)
    raw = vdf_path.read_text(encoding="utf-8", errors="surrogateescape")
    lines = raw.splitlines(keepends=True)

    out: list[str] = []
    depth = 0
    skip_target_depth: int | None = None
    waiting_open = False
    changed = False

    block_re = re.compile(r'^\s*"(?:Accounts|ConnectCache)"\s*(\{?)\s*$')
    inline_re = re.compile(r'^\s*"(?:Accounts|ConnectCache)"\s+"[^"]*"\s*$')

    for line in lines:
        opens, closes = count_unquoted_braces(line)
        if skip_target_depth is not None:
            depth += opens - closes
            if waiting_open and opens > 0:
                waiting_open = False
            if not waiting_open and depth <= skip_target_depth:
                skip_target_depth = None
            continue

        if depth == 4:
            m_block = block_re.match(line)
            if m_block:
                changed = True
                skip_target_depth = depth
                depth += opens - closes
                waiting_open = not bool(m_block.group(1))
                if not waiting_open and depth <= skip_target_depth:
                    skip_target_depth = None
                continue
            if inline_re.match(line):
                changed = True
                depth += opens - closes
                continue

        out.append(line)
        depth += opens - closes

    if changed:
        write_atomic_text(vdf_path, "".join(out), mode)


if stage_sys.is_dir():
    scrub_nm_connections(stage_sys / "nm-connections")

if stage_home.is_dir():
    vivaldi_dir = stage_home / ".config" / "vivaldi"
    scrub_json_file(vivaldi_dir / "Local State", scrub_vivaldi_local_state)
    scrub_json_file(vivaldi_dir / "Default" / "Preferences", scrub_vivaldi_preferences)

    cursor_gs = stage_home / ".config" / "Cursor" / "User" / "globalStorage"
    scrub_json_file(cursor_gs / "storage.json", scrub_cursor_storage_json)
    scrub_cursor_state_db(cursor_gs / "state.vscdb")

    scrub_steam_config_vdf(stage_home / ".local" / "share" / "Steam" / "config" / "config.vdf")
PYEOF
}

scrub_new_device_stage() {
  local stage_root=${1%/} preserve_target_home=${2:-}
  local stage_sys="${stage_root}/run/restic-backups-home/system"
  local stage_home="${stage_root}/home/mitac"

  printf '\n--new-device: 別端末と衝突する端末 ID・P2P 鍵・VPN/BT 状態・認証トークンを初期化しています...\n' >&2

  if [[ -d $stage_sys ]]; then
    local sub
    for sub in tailscale cloudflare-warp bluetooth; do
      remove_staged_path "${stage_sys}/${sub}"
    done
  fi

  if [[ -d $stage_home ]]; then
    if [[ -n $preserve_target_home ]] &&
       [[ -d "${preserve_target_home}/MySettings/.git" || -d "${preserve_target_home}/MySettings/hosts" ]]; then
      if [[ -e "${stage_home}/MySettings" || -L "${stage_home}/MySettings" ]]; then
        printf '既存の %s/MySettings を保持するため、スナップショット側の MySettings は上書きしません。\n' "$preserve_target_home" >&2
        remove_staged_path "${stage_home}/MySettings"
      fi
    fi

    local -a remove_rel_paths=(
      # Bitwarden CLI (rbw): keep current device registration/config, never clone device_id
      ".local/share/rbw"
      ".cache/rbw"
      ".config/rbw"

      # P2P / KVM / Remote desktop identities (keep lan-mouse config.toml, Parsec config.*, RQuickShare .settings.json)
      ".local/share/app.uniclipboard.desktop"
      ".local/state/app.uniclipboard.desktop"
      ".config/lan-mouse/lan-mouse.pem"
      ".local/share/org.localsend.localsend_app/shared_preferences.json"
      ".local/share/dev.mandre.rquickshare/storage"
      ".local/share/dev.mandre.rquickshare/mediakeys"
      ".parsec-persistent"
      ".parsec/user.bin"
      ".parsec/appdata.json"
      ".parsec/metrics_client.json"
      ".parsec/lock"
      ".parsec/log.txt"

      # Vivaldi sync/account caches (keeps Bookmarks, Notes, Preferences UI/extensions)
      ".config/vivaldi/Default/Sync App Settings"
      ".config/vivaldi/Default/Sync Extension Settings"
      ".config/vivaldi/Default/SyncedFiles"
      ".config/vivaldi/Default/AccountBookmarks"
      ".config/vivaldi/Default/Account Web Data"
      ".config/vivaldi/Default/Account Web Data-journal"
      ".config/vivaldi/Default/Login Data For Account"
      ".config/vivaldi/Default/Login Data For Account-journal"
      ".config/vivaldi/Default/trusted_vault.pb"
      ".config/vivaldi/Default/Sessions"

      # Cursor non-Chromium identity/host keys
      ".config/Cursor/machineid"
      ".config/Cursor/code.lock"
      ".config/Cursor/User/globalStorage/anysphere.cursor-agent-host"
      ".config/Cursor/User/globalStorage/mcp-oauth-attempts"

      # Codex CLI auth & device identity (keeps config.toml, skills, plugins, sessions)
      ".codex/auth.json"
      ".codex/installation_id"
      ".codex/.sqlite-maintenance.lock"
      ".codex/ipc"
      ".codex/tmp"
      ".codex/.tmp"
      ".codex/project-metadata-locks"
      ".codex/thread-writer-locks"
      ".codex/.codex-global-state.json"
      ".codex/.codex-global-state.json.bak"

      # Codex / ChatGPT desktop IDs
      ".config/Codex/.codex-tpp-local-executor-installation-id"
      ".config/Codex/Global Shortcuts Profile ID"
      ".config/Codex/Local State"
      ".config/Codex/artifact-sessions"

      # Grok Bot tokens & persistence
      ".config/Grok Bot/sand-secrets.json"
      ".config/Grok Bot/sand-client-persistence"
      ".config/Grok Bot/box-secrets-push-state.v1.json"
      ".config/Grok Bot/desktop-status.json"

      # Steam credentials (keeps libraryfolders.vdf / depots / ShaderCacheManager)
      ".local/share/Steam/config/loginusers.vdf"
      ".local/share/Steam/.crash"

      # AI CLI OAuth / installation UUIDs
      ".local/share/opencode/auth.json"
      ".gemini/antigravity-cli/installation_id"
      ".claude/.credentials.json"
    )

    local rel
    for rel in "${remove_rel_paths[@]}"; do
      remove_staged_path "${stage_home}/${rel}"
    done

    local -a chromium_dirs=(
      ".config/vivaldi/Default"
      ".config/Cursor"
      ".config/Codex"
      ".config/Codex/Default"
      ".config/Grok Bot"
      ".config/discord"
    )
    local cdir
    for cdir in "${chromium_dirs[@]}"; do
      purge_chromium_auth_artifacts "${stage_home}/${cdir}"
    done

    if [[ -d "${stage_home}/.config" ]]; then
      find "${stage_home}/.config" -maxdepth 3 \
        \( -name 'SingletonLock' -o -name 'SingletonSocket' -o -name 'SingletonCookie' \) \
        -delete 2>/dev/null || true
    fi

    local -a glob_paths=(
      "${stage_home}/.codex/..codex-global-state.json"*
      "${stage_home}/.codex/state_"*.sqlite*
      "${stage_home}/.local/share/Steam/ssfn"*
      "${stage_home}/.mozilla/firefox/"*/signedInUser.json
      "${stage_home}/.mozilla/firefox/"*/cookies.sqlite*
      "${stage_home}/.mozilla/firefox/"*/.parentlock
      "${stage_home}/.mozilla/firefox/"*/lock
    )
    local gp
    for gp in "${glob_paths[@]}"; do
      remove_staged_path "$gp"
    done
  fi

  scrub_new_device_structured "$stage_sys" "$stage_home"
}

print_new_device_checklist() {
  cat <<'EOF'

新規端末 (--new-device) の初回サインイン・確認項目:
  - ネットワーク: 保存済み Wi-Fi の interface-name / mac-address 縛りを解除済み（agenix 管理なら自動復元）
  - VPN / Bluetooth: Tailscale（`tailscale-authkey.age` が無ければ `sudo tailscale up`）/ Cloudflare WARP / Bluetooth ペアリング
  - 開発認証 / SSH: `agenix-master-key` 導入＋`rebuild` 後、gh / SSH 鍵 / AI 環境変数が自動展開
  - ブラウザ・アプリ: Vivaldi (Vivaldi Sync 再サインイン) / Cursor / ChatGPT & Codex / Grok Bot / Discord / Steam
  - P2P / KVM: UniClipboard / Lan Mouse / LocalSend / RQuickShare / Parsec
  - バックアップ: `rebuild` 後に `backup status`（agenix 管理なら `rbw unlock` 不要で自動バックアップ可）
EOF
}

main() {
  set -euo pipefail
  umask 077
  parse_args "$@"
  if (( HELP_REQUESTED == 1 )); then
    usage
    return 0
  fi
  local explicit_target=$EXPLICIT_TARGET
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

  local resolved_repo
  resolved_repo=$(resolve_repository "$FROM_HOST" "$EXPLICIT_REPO")

  check_platform
  ensure_tools "$@"
  if (( AGENIX_ONLY == 1 )); then
    maybe_bootstrap_agenix_from_rbw "$root_prefix" 1
    printf '\nagenix マスター復号鍵の導入が完了しました: %s/etc/agenix/master.key\n' "${root_prefix%/}"
    return 0
  fi
  if [[ $resolved_repo == rclone:gdrive:* ]]; then
    ensure_gdrive_remote
  fi

  export RESTIC_REPOSITORY="$resolved_repo"
  printf '復元元リポジトリ: %s\n' "$RESTIC_REPOSITORY" >&2

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
    if ! snapshots_json=$(restic snapshots --json latest); then
      if [[ -z $FROM_HOST && -z $EXPLICIT_REPO ]]; then
        printf 'ヒント: %s を開けませんでした。別端末のバックアップからは --from <host> --new-device を指定してください。\n' "$RESTIC_REPOSITORY" >&2
      fi
      exit 1
    fi
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
    if (( NEW_DEVICE == 1 )); then
      scrub_new_device_stage "$target" ""
    fi
    if [[ -d "${target}/home/mitac" ]]; then
      repair_vivaldi_extensions_from_crx "${target}/home/mitac"
    fi
    printf '%s\n' "$snapshot_id" > "$target/.restored-snapshot-id"
    printf '\n復元と検証が完了しました。\n'
    printf '展開先: %s\n' "$target"
    printf 'ホーム: %s/home/mitac\n' "$target"
    printf 'システム状態: %s/run/restic-backups-home/system\n' "$target"
    printf 'フォント: %s/home/mitac/Documents/hiragino-otf\n' "$target"
    if (( NEW_DEVICE == 1 )); then
      print_new_device_checklist
    fi
    return 0
  fi

  local stage_dir
  stage_dir=$(mktemp -d "${parent%/}/${stage_prefix}-XXXXXXXX")
  chmod 700 -- "$stage_dir"
  printf '一時展開先 (%s) へ検証付きで展開しています...\n' "$stage_dir" >&2
  restic restore "$snapshot_id" --target "$stage_dir" --verify

  if (( NEW_DEVICE == 1 )); then
    scrub_new_device_stage "$stage_dir" "$target_home"
  fi
  if [[ -d "${stage_dir}/home/mitac" ]]; then
    repair_vivaldi_extensions_from_crx "${stage_dir}/home/mitac"
  fi

  resolve_rclone_config
  local preserved_rclone=""
  if [[ -n ${RCLONE_CONFIG:-} && -f $RCLONE_CONFIG ]] && (( GDRIVE_CONFIGURED_THIS_RUN == 1 || NEW_DEVICE == 1 )); then
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
  maybe_bootstrap_agenix_from_rbw "$root_prefix" 0

  printf '\n復元と検証が完了しました。\n'
  printf 'スナップショット: %s\n' "$snapshot_id"
  printf 'ホーム: %s\n' "$target_home"
  if (( AGENIX_KEY_INSTALLED == 1 )); then
    printf 'agenix マスター鍵: %s/etc/agenix/master.key\n' "$root_prefix"
  fi
  if (( NEW_DEVICE == 1 )); then
    printf 'システム状態: %s/etc/NetworkManager/system-connections（tailscale / cloudflare-warp / bluetooth は --new-device により除外）\n' "$root_prefix"
  else
    printf 'システム状態: %s/etc/NetworkManager/system-connections, %s/var/lib/{bluetooth,cloudflare-warp,tailscale}\n' "$root_prefix" "$root_prefix"
  fi
  printf 'フォント（バックアップ時）: %s/Documents/hiragino-otf\n' "$target_home"
  printf '%s/MySettings から NixOS を再ビルドする際、Documents/hiragino-otf がある場合は --impure を付けてください。\n' "$target_home"
  if (( NEW_DEVICE == 1 )); then
    print_new_device_checklist
  fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
