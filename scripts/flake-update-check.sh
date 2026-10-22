#!/usr/bin/env bash
# Compare pinned .deb versions and GitHub flake inputs to upstream tips.
# Writes $XDG_RUNTIME_DIR/flake-update-status for waybar (does not mutate the flake).
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

status_file="${XDG_RUNTIME_DIR:-/tmp}/flake-update-status"
flake_nix="$root/flake.nix"
flake_lock="$root/flake.lock"

outdated=()
fetch_ok=1

note() {
  outdated+=("$1")
}

fail_fetch() {
  fetch_ok=0
  printf 'flake-update-check: %s\n' "$1" >&2
}

current_ver() {
  # $1 = attr name in flake.nix (e.g. chatgptVersion)
  sed -n "s/.*${1}[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$flake_nix" | head -n1
}

# --- UniClipboard ---
uc_cur="$(current_ver uniclipboardVersion)"
if uc_json="$(curl -fsSL --max-time 20 https://api.github.com/repos/UniClipboard/UniClipboard/releases/latest 2>/dev/null)"; then
  uc_tag="$(printf '%s\n' "$uc_json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  uc_ver="${uc_tag#v}"
  if [[ -n "$uc_ver" && -n "$uc_cur" && "$uc_ver" != "$uc_cur" ]]; then
    note "UniClipboard ${uc_cur}→${uc_ver}"
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
    note "ChatGPT ${chatgpt_cur}→${chatgpt_ver}"
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
    note "Grok Bot ${grok_cur}→${grok_bot_ver}"
  fi
else
  fail_fetch "Grok Bot download page fetch failed"
fi

# --- GitHub flake inputs (root only; skip file/path) ---
py=(python3)
if ! command -v python3 >/dev/null 2>&1; then
  py=(nix shell nixpkgs#python3 --command python3)
fi

mapfile -t flake_notes < <(
  "${py[@]}" - "$flake_lock" <<'PY' 2>/dev/null || true
import json, sys, urllib.error, urllib.request

lock = json.load(open(sys.argv[1]))
nodes = lock["nodes"]
root_inputs = nodes["root"]["inputs"]


def tip_sha(owner: str, repo: str, ref: str) -> str:
    # Prefer git/ref API (branch/tag); fall back to commits endpoint.
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "flake-update-check"}
    candidates = [
        f"https://api.github.com/repos/{owner}/{repo}/git/ref/heads/{ref}",
        f"https://api.github.com/repos/{owner}/{repo}/git/ref/tags/{ref}",
        f"https://api.github.com/repos/{owner}/{repo}/commits/{ref}",
    ]
    if ref == "HEAD":
        candidates = [
            f"https://api.github.com/repos/{owner}/{repo}/commits/HEAD",
        ]
    for url in candidates:
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                data = json.load(resp)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                continue
            raise
        if "object" in data and isinstance(data["object"], dict):
            sha = data["object"].get("sha") or ""
            # Annotated tags point at tag objects; resolve commit if needed.
            if data["object"].get("type") == "tag":
                treq = urllib.request.Request(
                    f"https://api.github.com/repos/{owner}/{repo}/git/tags/{sha}",
                    headers=headers,
                )
                with urllib.request.urlopen(treq, timeout=20) as tresp:
                    tdata = json.load(tresp)
                return (tdata.get("object") or {}).get("sha") or sha
            return sha
        if "sha" in data:
            return data["sha"] or ""
    return ""


for name, node_key in sorted(root_inputs.items()):
    node = nodes[node_key]
    original = node.get("original") or {}
    locked = node.get("locked") or {}
    if original.get("type") != "github" and locked.get("type") != "github":
        continue
    owner = locked.get("owner") or original.get("owner")
    repo = locked.get("repo") or original.get("repo")
    rev = locked.get("rev")
    if not owner or not repo or not rev:
        continue
    ref = original.get("ref") or "HEAD"
    try:
        tip = tip_sha(owner, repo, ref)
    except Exception:
        print(f"__FAIL__{name}", flush=True)
        continue
    if tip and tip != rev:
        print(f"{name}", flush=True)
PY
)

for line in "${flake_notes[@]+"${flake_notes[@]}"}"; do
  [[ -z "$line" ]] && continue
  if [[ "$line" == __FAIL__* ]]; then
    fail_fetch "git ls-remote failed for ${line#__FAIL__}"
  else
    note "$line"
  fi
done

n="${#outdated[@]}"

# Human-readable stdout (cheatsheet / terminal).
if ((n == 0)); then
  if ((fetch_ok == 0)); then
    printf 'flake-update-check: no confirmed updates (some fetches failed)\n'
  else
    printf 'flake-update-check: up to date\n'
  fi
else
  printf 'flake-update-check: %d update(s)\n' "$n"
  for item in "${outdated[@]}"; do
    printf '  - %s\n' "$item"
  done
fi

# On total fetch failure with nothing found, keep previous status file.
if ((n == 0 && fetch_ok == 0)); then
  exit 0
fi

tooltip="$(
  if ((n == 0)); then
    printf '更新なし'
  else
    printf '%s' "${outdated[0]}"
    i=1
    while ((i < n)); do
      printf '\n%s' "${outdated[i]}"
      i=$((i + 1))
    done
  fi
)"

json_out="$(
  "${py[@]}" - "$n" "$tooltip" <<'PY'
import json, sys
n = int(sys.argv[1])
tooltip = sys.argv[2]
if n == 0:
    obj = {"text": "", "class": "idle", "tooltip": tooltip}
elif n == 1:
    obj = {"text": "upd", "class": "available", "tooltip": tooltip}
else:
    obj = {"text": f"upd {n}", "class": "available", "tooltip": tooltip}
print(json.dumps(obj, ensure_ascii=False))
PY
)"

tmp="${status_file}.tmp.$$"
printf '%s\n' "$json_out" >"$tmp" && mv -f "$tmp" "$status_file"
pkill -SIGRTMIN+9 -x waybar >/dev/null 2>&1 || true
exit 0
