#!/usr/bin/env bash
# Compare pinned .deb versions and GitHub flake inputs to upstream tips.
# For nixpkgs / nixpkgs-cursor, list watched apps that changed (GitHub compare).
# Writes $XDG_RUNTIME_DIR/flake-update-status for waybar (does not mutate the flake).
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

status_file="${XDG_RUNTIME_DIR:-/tmp}/flake-update-status"
flake_nix="$root/flake.nix"
flake_lock="$root/flake.lock"
flake_py="$root/scripts/flake-update-check-flake.py"

# Records: icon<TAB>bar_label<TAB>tooltip_line
outdated=()
fetch_ok=1

note() {
  outdated+=("$1"$'\t'"$2"$'\t'"$3")
}

fail_fetch() {
  fetch_ok=0
  printf 'flake-update-check: %s\n' "$1" >&2
}

current_ver() {
  sed -n "s/.*${1}[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$flake_nix" | head -n1
}

py=(python3)
if ! command -v python3 >/dev/null 2>&1; then
  py=(nix shell nixpkgs#python3 --command python3)
fi

# --- UniClipboard ---
uc_cur="$(current_ver uniclipboardVersion)"
if uc_json="$(curl -fsSL --max-time 20 https://api.github.com/repos/UniClipboard/UniClipboard/releases/latest 2>/dev/null)"; then
  uc_tag="$(printf '%s\n' "$uc_json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  uc_ver="${uc_tag#v}"
  if [[ -n "$uc_ver" && -n "$uc_cur" && "$uc_ver" != "$uc_cur" ]]; then
    note $'\uf0ea' "uc" "UniClipboard ${uc_cur}→${uc_ver}"
  fi
else
  fail_fetch "UniClipboard release fetch failed"
fi

# --- ChatGPT ---
chatgpt_cur="$(current_ver chatgptVersion)"
if chatgpt_ver="$(
  curl -fsSL --max-time 20 https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-amd64/Packages 2>/dev/null |
    awk '/^Package: chatgpt$/{p=1;next} p&&/^Version:/{print $2;exit} p&&/^$/{exit}'
)"; then
  if [[ -n "$chatgpt_ver" && -n "$chatgpt_cur" && "$chatgpt_ver" != "$chatgpt_cur" ]]; then
    note $'\uf075' "gpt" "ChatGPT ${chatgpt_cur}→${chatgpt_ver}"
  fi
else
  fail_fetch "ChatGPT Packages fetch failed"
fi

# --- Grok Bot ---
grok_cur="$(current_ver grokBotVersion)"
if grok_bot_url="$(
  curl -fsSL --max-time 20 https://cursor.com/download/bot 2>/dev/null |
    sed -n 's/.*\(https:\/\/downloads\.cursor\.com\/grokbot\/stable\/[^"]*linux\/x64\/grok-bot_[^"]*_amd64\.deb\).*/\1/p' |
    head -n1
)"; then
  grok_bot_ver="$(printf '%s\n' "$grok_bot_url" | sed -n 's/.*grok-bot_\([^_]*\)_amd64\.deb/\1/p')"
  if [[ -n "$grok_bot_ver" && -n "$grok_cur" && "$grok_bot_ver" != "$grok_cur" ]]; then
    note $'\uf544' "grok" "Grok Bot ${grok_cur}→${grok_bot_ver}"
  fi
else
  fail_fetch "Grok Bot download page fetch failed"
fi

# --- GitHub flake inputs (+ nixpkgs watched apps via compare) ---
mapfile -t flake_notes < <("${py[@]}" "$flake_py" "$flake_lock" 2>/dev/null || true)

for line in "${flake_notes[@]+"${flake_notes[@]}"}"; do
  [[ -z "$line" ]] && continue
  if [[ "$line" == __FAIL__* ]]; then
    fail_fetch "GitHub tip/compare failed for ${line#__FAIL__}"
  elif [[ "$line" == REC$'\t'* ]]; then
    IFS=$'\t' read -r _rec icon short tip <<<"$line"
    note "$icon" "$short" "$tip"
  fi
done

n="${#outdated[@]}"

if ((n == 0)); then
  if ((fetch_ok == 0)); then
    printf 'flake-update-check: no confirmed updates (some fetches failed)\n'
  else
    printf 'flake-update-check: up to date\n'
  fi
else
  printf 'flake-update-check: %d update(s)\n' "$n"
  for rec in "${outdated[@]}"; do
    IFS=$'\t' read -r icon short tip <<<"$rec"
    printf '  - %s %s  %s\n' "$icon" "$short" "$tip"
  done
fi

if ((n == 0 && fetch_ok == 0)); then
  exit 0
fi

export FUC_N="$n"
export FUC_RECORDS="$(
  if ((n > 0)); then
    printf '%s\n' "${outdated[@]}"
  fi
)"

json_out="$(
  "${py[@]}" <<'PY'
import json, os

n = int(os.environ.get("FUC_N", "0"))
raw = os.environ.get("FUC_RECORDS", "")
recs = []
for line in raw.splitlines():
    parts = line.split("\t", 2)
    if len(parts) == 3:
        recs.append(tuple(parts))

if n == 0 or not recs:
    obj = {"text": "", "class": "idle", "tooltip": "更新なし"}
else:
    # Refresh header, then one icon per update (narrow left bar).
    lines = ["\uf021"]
    tips = []
    for icon, short, tip in recs:
        lines.append(icon if icon else short)
        tips.append(f"{icon} {tip}".strip() if icon else tip)
    obj = {
        "text": "\n".join(lines),
        "class": "available",
        "tooltip": "\n".join(tips),
    }
print(json.dumps(obj, ensure_ascii=False))
PY
)"

tmp="${status_file}.tmp.$$"
printf '%s\n' "$json_out" >"$tmp" && mv -f "$tmp" "$status_file"
pkill -SIGRTMIN+9 -x waybar >/dev/null 2>&1 || true
exit 0
