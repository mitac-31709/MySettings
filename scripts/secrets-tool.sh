#!/usr/bin/env bash
# Declarative secrets helper combining Bitwarden (rbw) and agenix.
# Keeps plaintext master keys out of user space (/etc/agenix/master.key is 0400 root:root)
# and never writes decrypted secrets or tokens in git or terminal output.
set -euo pipefail

REPO_ROOT=""
if [[ $# -ge 1 && -f "${1}/flake.nix" ]]; then
  REPO_ROOT=$1
  shift
else
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

SECRETS_DIR="${REPO_ROOT}/secrets"
RULES_FILE="${SECRETS_DIR}/agenix-rules.nix"
PUBKEY_FILE="${SECRETS_DIR}/master-pubkey.txt"
RBW_AGENIX_ITEM="${RBW_AGENIX_ITEM:-agenix-master-key}"
RBW_RESTIC_ITEM="${RBW_RESTIC_ITEM:-restic-home}"
HOST_ROOT="${SECRETS_HOST_ROOT:-/}"
HOST_ROOT=${HOST_ROOT%/}
HOST_KEY_PATH="${HOST_ROOT}/etc/agenix/master.key"

export PATH="${PATH}:/run/wrappers/bin:/run/current-system/sw/bin"

TMP_CLEANUP_FILES=()
cleanup_secrets_tmp() {
  local f
  for f in "${TMP_CLEANUP_FILES[@]}"; do
    if [[ -n $f && -e $f ]]; then
      chmod u+w -- "$f" 2>/dev/null || true
      rm -f -- "$f" 2>/dev/null || true
    fi
  done
}
trap cleanup_secrets_tmp EXIT INT TERM

say() { printf '%s\n' "$*"; }
warn() { printf '警告: %s\n' "$*" >&2; }
die() { printf 'エラー: %s\n' "$*" >&2; exit 1; }

make_tmp_secret_file() {
  local base_dir="${XDG_RUNTIME_DIR:-/tmp}"
  local f
  umask 077
  f=$(mktemp "${base_dir%/}/mitac-secrets-XXXXXXXX")
  chmod 600 -- "$f"
  TMP_CLEANUP_FILES+=("$f")
  printf '%s' "$f"
}

run_sudo() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

trim_ws() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

confirm() {
  local prompt=$1 reply=""
  printf '%s [y/N] ' "$prompt"
  read -r reply || true
  case $reply in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_live_tools() {
  local -a missing_pkgs=() missing_cmds=()
  local cmd
  for cmd in age age-keygen rbw jq python3 nix-instantiate; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing_cmds+=("$cmd")
      case $cmd in
        age|age-keygen) missing_pkgs+=(nixpkgs#age) ;;
        rbw) missing_pkgs+=(nixpkgs#rbw) ;;
        jq) missing_pkgs+=(nixpkgs#jq) ;;
        python3) missing_pkgs+=(nixpkgs#python3) ;;
      esac
    fi
  done
  if (( ${#missing_pkgs[@]} > 0 )); then
    command -v nix >/dev/null 2>&1 || die "必要なツール (${missing_cmds[*]}) が見つかりません。"
    if [[ -z ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} ]]; then
      missing_pkgs+=(nixpkgs#pinentry-curses)
    else
      missing_pkgs+=(nixpkgs#pinentry-qt)
    fi
    say "nix shell で不足ツールを取得しています (${missing_cmds[*]})..."
    exec nix --extra-experimental-features 'nix-command flakes' shell \
      "${missing_pkgs[@]}" \
      --command bash "${BASH_SOURCE[0]}" "$REPO_ROOT" "$@"
  fi
}

ensure_rbw_unlocked() {
  command -v rbw >/dev/null 2>&1 || die "rbw コマンドが見つかりません。"
  local cfg_json cur_email rbw_conf conf_ro=0
  rbw_conf="${XDG_CONFIG_HOME:-$HOME/.config}/rbw/config.json"
  if [[ -L $rbw_conf && ! -w $rbw_conf ]] || { [[ -e $rbw_conf && ! -w $rbw_conf ]]; }; then
    conf_ro=1
  fi
  cfg_json=$(rbw config show 2>/dev/null || printf '{}')
  cur_email=$(jq -r '.email // empty' <<<"$cfg_json" 2>/dev/null || true)

  if [[ -z $cur_email ]]; then
    (( conf_ro == 0 )) || die "rbw 設定 ($rbw_conf) が未設定かつ読み取り専用です。"
    local email=""
    printf 'Bitwarden メールアドレス [Enter で mitac31709@gmail.com]: ' >&2
    IFS= read -r email || die "入力が中断されました。"
    email=$(trim_ws "$email")
    email=${email:-mitac31709@gmail.com}
    rbw config set email "$email"
    rbw config set base_url "${RBW_BASE_URL:-https://api.bitwarden.eu}"
    if [[ ${RBW_BASE_URL:-https://api.bitwarden.eu} == "https://api.bitwarden.eu" ]]; then
      rbw config set identity_url "https://identity.bitwarden.eu"
      rbw config set ui_url "https://vault.bitwarden.eu"
      rbw config set notifications_url "https://notifications.bitwarden.eu"
    fi
    if [[ -n ${DISPLAY:-} || -n ${WAYLAND_DISPLAY:-} ]] && command -v pinentry-qt >/dev/null 2>&1; then
      rbw config set pinentry "$(command -v pinentry-qt)"
    elif command -v pinentry-curses >/dev/null 2>&1; then
      rbw config set pinentry "$(command -v pinentry-curses)"
    fi
    rbw stop-agent >/dev/null 2>&1 || true
  fi

  if ! rbw unlocked >/dev/null 2>&1; then
    say "Bitwarden (rbw) をロック解除します..."
    rbw login >/dev/null 2>&1 || true
    rbw unlock || die "rbw unlock に失敗しました（初回端末は rbw register が必要な場合があります）。"
  fi
  rbw sync >/dev/null 2>&1 || true
}

extract_master_key_from_rbw() {
  local out_file=$1 raw_json="" candidate="" notes="" line=""
  raw_json=$(rbw get --raw "$RBW_AGENIX_ITEM" 2>/dev/null) || return 1
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$raw_json" || return 1

  candidate=$(jq -r '.data.password // empty' <<<"$raw_json" 2>/dev/null || true)
  candidate=$(trim_ws "$candidate")
  if [[ -n $candidate ]]; then
    if [[ $candidate == AGE-SECRET-KEY-1* ]] || [[ $candidate == *"BEGIN OPENSSH PRIVATE KEY"* ]]; then
      printf '%s\n' "$candidate" >"$out_file"
      chmod 600 -- "$out_file"
      return 0
    fi
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

derive_pubkey_from_identity() {
  local id_file=$1 pub=""
  if pub=$(age-keygen -y "$id_file" 2>/dev/null) && [[ $pub == age1* ]]; then
    printf '%s' "$pub"
    return 0
  fi
  if command -v ssh-keygen >/dev/null 2>&1 && pub=$(ssh-keygen -y -f "$id_file" 2>/dev/null) && [[ $pub == ssh-* ]]; then
    printf '%s' "$pub"
    return 0
  fi
  return 1
}

write_pubkey_file() {
  local pubkey=$1
  mkdir -p -- "$SECRETS_DIR"
  cat >"$PUBKEY_FILE" <<EOF
# Master age public key (non-secret) used by secrets/agenix-rules.nix.
# Generated once via \`secrets init\` (private key stays in Bitwarden item \`${RBW_AGENIX_ITEM}\`
# and at \`/etc/agenix/master.key\` on each host).
# Add one public key per line (\`age1...\` or \`ssh-ed25519 ...\`).
${pubkey}
EOF
}

read_configured_pubkeys() {
  [[ -f $RULES_FILE ]] || die "ルールファイルが見つかりません: $RULES_FILE"
  local pub_json
  pub_json=$(nix-instantiate --json --eval --strict -E "(let rules = import ${RULES_FILE}; in rules.\"restic-home-password.age\".publicKeys)") || return 1
  jq -r '.[]' <<<"$pub_json"
}

require_pubkeys() {
  local -a keys=()
  mapfile -t keys < <(read_configured_pubkeys)
  (( ${#keys[@]} > 0 )) || die "公開鍵が未設定です。先に \`secrets init\`（または \`secrets bootstrap\`）を実行してください。"
  printf '%s\n' "${keys[@]}"
}

encrypt_stdin_to_age() {
  local target_rel=$1
  local target_path="${SECRETS_DIR}/${target_rel}"
  local -a pubkeys=() age_args=()
  mapfile -t pubkeys < <(require_pubkeys)

  local pk
  for pk in "${pubkeys[@]}"; do
    age_args+=(-r "$pk")
  done

  local tmp_out
  tmp_out=$(make_tmp_secret_file)
  age "${age_args[@]}" -o "$tmp_out"
  mkdir -p -- "$(dirname -- "$target_path")"
  mv -f -- "$tmp_out" "$target_path"
  chmod 644 -- "$target_path"
  say "暗号化を保存しました: secrets/${target_rel}"
}

obtain_identity_file() {
  local tmp_id
  tmp_id=$(make_tmp_secret_file)
  if command -v rbw >/dev/null 2>&1 && rbw unlocked >/dev/null 2>&1; then
    if extract_master_key_from_rbw "$tmp_id" && derive_pubkey_from_identity "$tmp_id" >/dev/null; then
      printf '%s' "$tmp_id"
      return 0
    fi
  fi
  if run_sudo test -r "$HOST_KEY_PATH" 2>/dev/null; then
    run_sudo cat "$HOST_KEY_PATH" >"$tmp_id"
    chmod 600 -- "$tmp_id"
    if derive_pubkey_from_identity "$tmp_id" >/dev/null; then
      printf '%s' "$tmp_id"
      return 0
    fi
  fi
  ensure_rbw_unlocked
  extract_master_key_from_rbw "$tmp_id" || die "Bitwarden に項目 '$RBW_AGENIX_ITEM' が見つかりません。先に \`secrets init\` を実行してください。"
  derive_pubkey_from_identity "$tmp_id" >/dev/null || die "取得した '$RBW_AGENIX_ITEM' が有効な age / SSH 秘密鍵ではありません。"
  printf '%s' "$tmp_id"
}

install_host_master_key() {
  local root_prefix=${1:-$HOST_ROOT} key_file=$2
  root_prefix=${root_prefix%/}
  local dest_dir="${root_prefix}/etc/agenix"
  local dest_key="${dest_dir}/master.key"
  run_sudo install -d -m 0700 -o root -g root "$dest_dir"
  run_sudo install -m 0400 -o root -g root "$key_file" "$dest_key"
  say "マスター復号鍵をインストールしました: $dest_key (0400 root:root)"
}

cmd_bootstrap() {
  local root_prefix=${1:-$HOST_ROOT}
  ensure_rbw_unlocked
  local tmp_key pubkey
  tmp_key=$(make_tmp_secret_file)
  extract_master_key_from_rbw "$tmp_key" || die "Bitwarden 項目 '$RBW_AGENIX_ITEM' を取得できませんでした（項目名と保存内容を確認してください）。"
  pubkey=$(derive_pubkey_from_identity "$tmp_key") || die "項目 '$RBW_AGENIX_ITEM' の鍵形式が不正です。"
  install_host_master_key "$root_prefix" "$tmp_key"
  if [[ -d $SECRETS_DIR && -w $SECRETS_DIR ]] && [[ ! -s $PUBKEY_FILE || -z $(read_configured_pubkeys 2>/dev/null || true) ]]; then
    write_pubkey_file "$pubkey"
    say "公開鍵を書き込みました: secrets/master-pubkey.txt ($pubkey)"
  fi
}

cmd_init() {
  ensure_rbw_unlocked
  local tmp_key pubkey=""

  if [[ -f $PUBKEY_FILE ]] && (( $(read_configured_pubkeys | wc -l) > 0 )); then
    say "既存の公開鍵設定を検出しました: secrets/master-pubkey.txt"
  fi

  tmp_key=$(make_tmp_secret_file)
  if extract_master_key_from_rbw "$tmp_key"; then
    pubkey=$(derive_pubkey_from_identity "$tmp_key") || die "既存の Bitwarden '$RBW_AGENIX_ITEM' が有効な鍵ではありません。"
    say "Bitwarden に既存の '$RBW_AGENIX_ITEM' が見つかりました（新規生成せず流用します）。"
    write_pubkey_file "$pubkey"
    install_host_master_key "$HOST_ROOT" "$tmp_key"
    say "公開鍵: $pubkey"
    return 0
  fi

  say "新しい agenix 共通マスター鍵を生成します..."
  local gen_out secret_line=""
  gen_out=$(age-keygen 2>/dev/null)
  secret_line=$(printf '%s\n' "$gen_out" | grep '^AGE-SECRET-KEY-1' | head -n1 || true)
  pubkey=$(printf '%s\n' "$gen_out" | sed -n 's/^# public key: //p' | head -n1 || true)
  [[ -n $secret_line && -n $pubkey ]] || die "age-keygen の出力を解釈できませんでした。"
  printf '%s\n' "$secret_line" >"$tmp_key"
  chmod 600 -- "$tmp_key"

  local writer_script
  writer_script=$(make_tmp_secret_file)
  cat >"$writer_script" <<EOF
#!/bin/sh
set -eu
dest=\$1
cat >"\$dest" <<'KEYEOF'
${secret_line}
# MySettings agenix master private key (keep in Bitwarden; install at ${HOST_KEY_PATH} mode 0400)
public_key: ${pubkey}
KEYEOF
EOF
  chmod 700 -- "$writer_script"

  say "Bitwarden 項目 '$RBW_AGENIX_ITEM' へ秘密鍵を自動登録しています..."
  if VISUAL="$writer_script" EDITOR="$writer_script" rbw add "$RBW_AGENIX_ITEM"; then
    rbw sync >/dev/null 2>&1 || true
    local verify_tmp
    verify_tmp=$(make_tmp_secret_file)
    if ! extract_master_key_from_rbw "$verify_tmp"; then
      die "Bitwarden への登録検証に失敗しました。\`rbw get $RBW_AGENIX_ITEM\` を確認してください。"
    fi
  else
    die "\`rbw add $RBW_AGENIX_ITEM\` に失敗しました。先に秘密鍵が失われないよう中断しました。"
  fi

  write_pubkey_file "$pubkey"
  install_host_master_key "$HOST_ROOT" "$tmp_key"
  say ""
  say "初期化完了:"
  say "  - Bitwarden 項目: $RBW_AGENIX_ITEM（パスワード欄に保存済み・同期済み）"
  say "  - ホスト復号鍵  : $HOST_KEY_PATH (0400 root:root)"
  say "  - 公開鍵ファイル: secrets/master-pubkey.txt ($pubkey)"
}

normalize_secret_rel() {
  local arg=$1
  arg=${arg#secrets/}
  arg=${arg#./secrets/}
  if [[ $arg != *.age ]]; then
    arg="${arg}.age"
  fi
  printf '%s' "$arg"
}

cmd_edit() {
  (( $# >= 1 )) || die "使い方: secrets edit <name>"
  local rel target_path id_file agenix_bin
  rel=$(normalize_secret_rel "$1")
  target_path="${SECRETS_DIR}/${rel}"
  command -v agenix >/dev/null 2>&1 || die "agenix コマンドが見つかりません。"
  agenix_bin=$(command -v agenix)

  local exists_in_rules
  exists_in_rules=$(nix-instantiate --json --eval --strict -E "(let rules = import ${RULES_FILE}; in builtins.hasAttr \"${rel}\" rules)")
  [[ $exists_in_rules == "true" ]] || die "secrets/agenix-rules.nix に '$rel' のルールがありません。"
  require_pubkeys >/dev/null

  export EDITOR="${EDITOR:-$(command -v nvim || command -v vim || command -v vi || true)}"
  [[ -n $EDITOR ]] || die "EDITOR が設定されていません。"

  id_file=$(obtain_identity_file)

  if [[ $rel == "user-env.age" && ! -f $target_path ]]; then
    local seed_tmp
    seed_tmp=$(make_tmp_secret_file)
    cat >"$seed_tmp" <<'EOF'
# Personal CLI/API tokens loaded by bash & graphical session (KEY=VALUE, one per line).
# Example:
# OPENAI_API_KEY="sk-..."
# DEEPSEEK_API_KEY="sk-..."
# GEMINI_API_KEY="AIza..."
# ANTHROPIC_API_KEY="sk-ant-..."
EOF
    AGENIX_RULES="$RULES_FILE" "$agenix_bin" -i "$id_file" -e "$rel" <"$seed_tmp"
  fi

  AGENIX_RULES="$RULES_FILE" "$agenix_bin" -i "$id_file" -e "$rel"
}

cmd_rekey() {
  command -v agenix >/dev/null 2>&1 || die "agenix コマンドが見つかりません。"
  require_pubkeys >/dev/null
  local id_file
  id_file=$(obtain_identity_file)
  local -a rules_files=()
  mapfile -t rules_files < <(nix-instantiate --json --eval --strict -E "(builtins.attrNames (import ${RULES_FILE}))" | jq -r '.[]')

  local rel p any=0
  for rel in "${rules_files[@]}"; do
    p="${SECRETS_DIR}/${rel}"
    if [[ -f $p ]]; then
      any=1
      say "再暗号化: secrets/${rel}"
      EDITOR=: AGENIX_RULES="$RULES_FILE" agenix -i "$id_file" -e "$rel"
    fi
  done
  (( any == 1 )) || say "再暗号化対象の .age ファイルはまだありません。"
}

cmd_check() {
  local verify_decrypt=0
  if [[ ${1:-} == "--decrypt" ]]; then
    verify_decrypt=1
  fi
  require_pubkeys >/dev/null
  local -a rules_files=()
  mapfile -t rules_files < <(nix-instantiate --json --eval --strict -E "(builtins.attrNames (import ${RULES_FILE}))" | jq -r '.[]')

  local id_file=""
  if (( verify_decrypt == 1 )); then
    id_file=$(obtain_identity_file)
  fi

  local rel p failed=0 present=0
  for rel in "${rules_files[@]}"; do
    p="${SECRETS_DIR}/${rel}"
    if [[ ! -f $p ]]; then
      printf '  - %-28s (未作成・スキップ)\n' "$rel"
      continue
    fi
    present=$((present + 1))
    local first_line="" has_recipient=0
    IFS= read -r first_line <"$p" || true
    if [[ $first_line == "age-encryption.org/v1" ]]; then
      if grep -qE '^-> (X25519|ssh-ed25519|ssh-rsa) ' "$p"; then
        has_recipient=1
      fi
    elif [[ $first_line == "-----BEGIN AGE ENCRYPTED FILE-----" ]]; then
      has_recipient=1
    fi
    if (( has_recipient == 0 )); then
      printf '  ✗ %-28s (age ヘッダ不正)\n' "$rel"
      failed=1
      continue
    fi
    if (( verify_decrypt == 1 )); then
      if age --decrypt -i "$id_file" -o /dev/null "$p" 2>/dev/null; then
        printf '  ✓ %-28s (ヘッダ・復号 OK)\n' "$rel"
      else
        printf '  ✗ %-28s (復号失敗)\n' "$rel"
        failed=1
      fi
    else
      printf '  ✓ %-28s (暗号化ヘッダ OK)\n' "$rel"
    fi
  done
  say "確認完了: 作成済み ${present}/${#rules_files[@]} 件"
  (( failed == 0 )) || exit 1
}

cmd_status() {
  say "リポジトリ: $REPO_ROOT"
  local -a pks=()
  mapfile -t pks < <(read_configured_pubkeys 2>/dev/null || true)
  if (( ${#pks[@]} > 0 )); then
    say "公開鍵    : secrets/master-pubkey.txt (${pks[*]})"
  else
    say "公開鍵    : 未設定（先に \`secrets init\` または \`secrets bootstrap\`）"
  fi
  if [[ -d "${HOST_ROOT}/etc/agenix" ]]; then
    say "鍵配置    : ${HOST_ROOT}/etc/agenix ディレクトリ存在（詳細は \`sudo ls -la ${HOST_ROOT}/etc/agenix\`）"
  else
    say "鍵配置    : ${HOST_ROOT}/etc/agenix 未作成"
  fi
  say ""
  say "宣言シークレット状態 (.age / /run/agenix):"
  local -a rules_files=()
  mapfile -t rules_files < <(nix-instantiate --json --eval --strict -E "(builtins.attrNames (import ${RULES_FILE}))" | jq -r '.[]')
  local rel age_mark run_name run_mark
  for rel in "${rules_files[@]}"; do
    if [[ -f "${SECRETS_DIR}/${rel}" ]]; then
      age_mark="あり"
    else
      age_mark="なし"
    fi
    case $rel in
      id-wsl-builder.age)
        run_name="id-wsl-builder-user"
        ;;
      *)
        run_name="${rel%.age}"
        ;;
    esac
    if [[ -e "/run/agenix/${run_name}" ]]; then
      run_mark="復号済み (/run/agenix/${run_name})"
    else
      run_mark="未復号（未作成または rebuild 前）"
    fi
    printf '  - %-26s [%s]  %s\n' "$rel" "$age_mark" "$run_mark"
  done
}

cmd_import_restic() {
  ensure_rbw_unlocked
  require_pubkeys >/dev/null
  local raw_json pw=""
  if ! raw_json=$(rbw get --raw "$RBW_RESTIC_ITEM" 2>/dev/null) || [[ -z $raw_json ]]; then
    say "Bitwarden 項目 '$RBW_RESTIC_ITEM' が未登録です。"
    confirm "40 文字の新しい restic 暗号化キーを生成して Bitwarden '$RBW_RESTIC_ITEM' に保存しますか？" || die "中断しました。"
    rbw generate 40 "$RBW_RESTIC_ITEM"
    rbw sync >/dev/null 2>&1 || true
    raw_json=$(rbw get --raw "$RBW_RESTIC_ITEM")
  fi
  pw=$(jq -j '.data.password // empty' <<<"$raw_json")
  [[ -n $pw ]] || die "Bitwarden 項目 '$RBW_RESTIC_ITEM' のパスワード欄が空です。"
  printf '%s' "$pw" | encrypt_stdin_to_age "restic-home-password.age"
  say "注: Bitwarden '$RBW_RESTIC_ITEM' にも同一パスワードを保持しています（他端末確認用）。"
}

cmd_import_rclone() {
  require_pubkeys >/dev/null
  local src="${XDG_CONFIG_HOME:-$HOME/.config}/rclone/rclone.conf"
  [[ -f $src ]] || die "rclone 設定が見つかりません: $src（先に \`backup setup\` 等を実行）"
  grep -q '^\[gdrive\]' "$src" || die "$src に [gdrive] セクションが見つかりません。"
  encrypt_stdin_to_age "rclone-conf.age" <"$src"
  say "ヒント: 他端末からの復元用（Bitwarden '$RBW_RESTIC_ITEM' 同期）には \`backup reconnect --help\` / OAuth メモ欄も維持してください。"
}

cmd_import_ssh() {
  require_pubkeys >/dev/null
  local builder_priv="$HOME/.ssh/id_wsl_builder"
  local builder_pub="$HOME/.ssh/id_wsl_builder.pub"
  if [[ -f $builder_priv && ! -L $builder_priv ]]; then
    encrypt_stdin_to_age "id-wsl-builder.age" <"$builder_priv"
    if [[ -f $builder_pub ]]; then
      install -m 0644 "$builder_pub" "${SECRETS_DIR}/id-wsl-builder.pub"
      say "公開鍵をコピーしました: secrets/id-wsl-builder.pub"
    fi
  elif [[ -L $builder_priv ]]; then
    say "$builder_priv は既に agenix シンボリックリンクです。"
  else
    warn "$builder_priv が見つからないためスキップしました。"
  fi

  local personal_priv="$HOME/.ssh/id_ed25519"
  local personal_pub="$HOME/.ssh/id_ed25519.pub"
  if [[ -f $personal_priv && ! -L $personal_priv ]]; then
    if confirm "個人の ~/.ssh/id_ed25519 も secrets/id-ed25519.age へ暗号化しますか？"; then
      encrypt_stdin_to_age "id-ed25519.age" <"$personal_priv"
      if [[ -f $personal_pub ]]; then
        install -m 0644 "$personal_pub" "${SECRETS_DIR}/id-ed25519.pub"
        say "公開鍵をコピーしました: secrets/id-ed25519.pub"
      fi
    fi
  fi
}

cmd_import_gh() {
  require_pubkeys >/dev/null
  command -v gh >/dev/null 2>&1 || die "gh コマンドが見つかりません。"
  local token="" login=""
  token=$(gh auth token 2>/dev/null || true)
  [[ -n $token ]] || die "gh が未ログインです（先に \`gh auth login\`）。"
  local gh_hosts="${XDG_CONFIG_HOME:-$HOME/.config}/gh/hosts.yml"
  if [[ -r $gh_hosts ]]; then
    login=$(sed -nE 's/^[[:space:]]+user:[[:space:]]*([^[:space:]]+).*$/\1/p' "$gh_hosts" | head -n1 || true)
  fi
  if [[ -z $login ]]; then
    login=$(gh auth status 2>&1 | sed -nE 's/.*account ([^ ]+).*/\1/p' | head -n1 || true)
  fi
  if [[ -z $login ]]; then
    login=$(gh api user --jq '.login' 2>/dev/null || true)
  fi
  [[ -n $login ]] || die "GitHub ユーザー名を特定できませんでした。"

  python3 - "$login" "$token" <<'PY' | encrypt_stdin_to_age "gh-hosts.yml.age"
import sys
login, token = sys.argv[1], sys.argv[2]
sys.stdout.write(
    f"github.com:\n"
    f"    git_protocol: https\n"
    f"    user: {login}\n"
    f"    oauth_token: {token}\n"
    f"    users:\n"
    f"        {login}:\n"
)
PY
}

cmd_import_wifi() {
  require_pubkeys >/dev/null
  local tmp_bundle
  tmp_bundle=$(make_tmp_secret_file)
  run_sudo python3 - "$tmp_bundle" <<'PY'
import configparser
import os
import pathlib
import sys

out_path = pathlib.Path(sys.argv[1])
src_dir = pathlib.Path("/etc/NetworkManager/system-connections")
if not src_dir.is_dir():
    print("エラー: /etc/NetworkManager/system-connections がありません。", file=sys.stderr)
    sys.exit(1)

entries = []
for p in sorted(src_dir.glob("*.nmconnection")):
    raw = p.read_text(encoding="utf-8", errors="replace")
    cp = configparser.ConfigParser(interpolation=None)
    cp.optionxform = str
    try:
        cp.read_string(raw)
    except configparser.Error:
        continue
    ctype = cp.get("connection", "type", fallback="?")
    cid = cp.get("connection", "id", fallback=p.stem)
    ssid = cp.get("wifi", "ssid", fallback="")
    km = cp.get("wifi-security", "key-mgmt", fallback="open/none")
    entries.append((p, cid, ctype, ssid, km, raw))

if not entries:
    print("保存済み .nmconnection が見つかりませんでした。", file=sys.stderr)
    sys.exit(1)

print("暗号化対象のネットワークプロファイルを選択してください（秘密値は表示しません）:")
for idx, (p, cid, ctype, ssid, km, _) in enumerate(entries, start=1):
    extra = f"ssid={ssid}, {km}" if ssid else km
    print(f"  {idx:2d}) {cid} [{ctype}; {extra}] ({p.name})")

print("入力例: all / wifi / 1,3,5 / q(中止)")
choice = input("選択 [wifi]: ").strip() or "wifi"
if choice.lower() in {"q", "quit"}:
    sys.exit(2)

selected = []
if choice.lower() == "all":
    selected = entries
elif choice.lower() == "wifi":
    selected = [e for e in entries if e[2] == "802-11-wireless"]
else:
    idxs = set()
    for part in choice.split(","):
        part = part.strip()
        if not part.isdigit():
            print(f"エラー: 不正な番号です: {part}", file=sys.stderr)
            sys.exit(1)
        i = int(part)
        if i < 1 or i > len(entries):
            print(f"エラー: 範囲外の番号です: {i}", file=sys.stderr)
            sys.exit(1)
        idxs.add(i)
    selected = [entries[i - 1] for i in sorted(idxs)]

if not selected:
    print("選択されたプロファイルが 0 件でした。", file=sys.stderr)
    sys.exit(1)

bundle_parts = []
for p, cid, ctype, ssid, km, raw in selected:
    lines = []
    for line in raw.splitlines(keepends=True):
        if line.lstrip().startswith(("interface-name=", "mac-address=")):
            continue
        lines.append(line)
    body = "".join(lines).strip()
    bundle_parts.append(f"# === {p.name} ===\n{body}\n")

out_path.write_text("\n".join(bundle_parts), encoding="utf-8")
os.chmod(out_path, 0o600)
print(f"{len(selected)} 件のプロファイルをバンドルしました（interface-name/mac-address 除去済み）。")
PY
  local rc=$?
  if (( rc == 2 )); then
    say "Wi-Fi 取り込みをスキップしました。"
    return 0
  elif (( rc != 0 )); then
    return "$rc"
  fi
  encrypt_stdin_to_age "nm-connections.age" <"$tmp_bundle"
  say "注意: 既存マシンの /etc/NetworkManager/system-connections に同一プロファイルが残っていると"
  say "      一覧で重複表示されることがあります（\`rebuild\` 後に自動接続を確認してから不要分を削除可）。"
}

cmd_set_tailscale_key() {
  require_pubkeys >/dev/null
  say "Tailscale の事前認証キー (tskey-auth-...) または OAuth シークレット (tskey-client-...) を入力してください。"
  say "※ 複数端末で使い回せる Reusable key（または OAuth + extraUpFlags tags）を推奨します（画面非表示）。"
  local key=""
  printf 'Tailscale Auth Key: ' >&2
  IFS= read -rs key || die "入力が中断されました。"
  printf '\n' >&2
  key=$(trim_ws "$key")
  [[ $key == tskey-* ]] || die "Tailscale キーは tskey- で始まる必要があります。"
  printf '%s' "$key" | encrypt_stdin_to_age "tailscale-authkey.age"
  if [[ $key == tskey-client-* ]]; then
    say "注意: OAuth クライアントシークレットの場合は services.tailscale.extraUpFlags に \"--advertise-tags=tag:...\" の設定が必要です。"
  fi
}

cmd_import_all() {
  cmd_init
  say ""
  if confirm "1/6 restic パスワードを Bitwarden ('${RBW_RESTIC_ITEM}') から暗号化しますか？"; then
    cmd_import_restic
  fi
  say ""
  if confirm "2/6 ~/.config/rclone/rclone.conf を暗号化しますか？"; then
    cmd_import_rclone
  fi
  say ""
  if confirm "3/6 ~/.ssh/id_wsl_builder（および任意で id_ed25519）を暗号化しますか？"; then
    cmd_import_ssh
  fi
  say ""
  if confirm "4/6 gh CLI トークンを secrets/gh-hosts.yml.age へ暗号化しますか？"; then
    cmd_import_gh
  fi
  say ""
  if confirm "5/6 保存済み Wi-Fi 設定を secrets/nm-connections.age へ暗号化しますか？"; then
    cmd_import_wifi
  fi
  say ""
  if confirm "6/6 Tailscale 事前認証/OAuth キーを secrets/tailscale-authkey.age へ登録しますか？"; then
    cmd_set_tailscale_key
  fi
  say ""
  if confirm "任意: 個人 API キー等 (secrets/user-env.age) を編集しますか？"; then
    cmd_edit "user-env.age"
  fi
  say ""
  say "次の手順:"
  say "  cd $REPO_ROOT && git add secrets/ && secrets check --decrypt && rebuild"
}

usage() {
  cat <<'EOF'
secrets — Bitwarden (rbw) × agenix 宣言的シークレット管理 CLI

使い方:
  secrets status                  設定済み公開鍵・.age・/run/agenix 復号状態を表示
  secrets init                    共通マスター age 鍵を生成し Bitwarden と /etc/agenix へ登録
  secrets bootstrap [ROOT_PREFIX] Bitwarden から /etc/agenix/master.key を導入（Live USB なら /mnt）
  secrets edit <name>             暗号化シークレットを作成・編集（rbw/ホスト鍵を透過利用）
  secrets rekey                   全 .age を最新の公開鍵ルールで再暗号化
  secrets check [--decrypt]       全 .age のヘッダ（--decrypt で復号）検証

既存環境からの暗号化取り込み:
  secrets import                  対話式ウィザードで全項目を順に取り込む
  secrets import-restic           Bitwarden restic-home → secrets/restic-home-password.age
  secrets import-rclone           ~/.config/rclone/rclone.conf → secrets/rclone-conf.age
  secrets import-ssh              ~/.ssh/id_wsl_builder 等 → secrets/id-wsl-builder.age
  secrets import-gh               gh auth token → secrets/gh-hosts.yml.age
  secrets import-wifi             NetworkManager 接続 → secrets/nm-connections.age
  secrets set-tailscale-key       Tailscale 事前認証/OAuth キー → secrets/tailscale-authkey.age
EOF
}

cmd="${1:-status}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  -h|--help|help)
    usage
    exit 0
    ;;
  status|st)
    ensure_live_tools "$cmd" "$@"
    cmd_status "$@"
    ;;
  init)
    ensure_live_tools "$cmd" "$@"
    cmd_init "$@"
    ;;
  bootstrap|bs)
    ensure_live_tools "$cmd" "$@"
    cmd_bootstrap "$@"
    ;;
  edit|e)
    ensure_live_tools "$cmd" "$@"
    cmd_edit "$@"
    ;;
  rekey|r)
    ensure_live_tools "$cmd" "$@"
    cmd_rekey "$@"
    ;;
  check|c)
    ensure_live_tools "$cmd" "$@"
    cmd_check "$@"
    ;;
  import)
    ensure_live_tools "$cmd" "$@"
    cmd_import_all "$@"
    ;;
  import-restic)
    ensure_live_tools "$cmd" "$@"
    cmd_import_restic "$@"
    ;;
  import-rclone)
    ensure_live_tools "$cmd" "$@"
    cmd_import_rclone "$@"
    ;;
  import-ssh)
    ensure_live_tools "$cmd" "$@"
    cmd_import_ssh "$@"
    ;;
  import-gh)
    ensure_live_tools "$cmd" "$@"
    cmd_import_gh "$@"
    ;;
  import-wifi)
    ensure_live_tools "$cmd" "$@"
    cmd_import_wifi "$@"
    ;;
  set-tailscale-key)
    ensure_live_tools "$cmd" "$@"
    cmd_set_tailscale_key "$@"
    ;;
  *)
    die "不明なサブコマンドです: $cmd（\`secrets --help\` を確認してください）"
    ;;
esac
