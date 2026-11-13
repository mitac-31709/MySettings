#!/usr/bin/env bash
# Bump versioned .deb URLs, then update every flake input except nixpkgs-cursor.
# nixpkgs and nixpkgs-cursor both track nixos-unstable; updating them together
# pins Cursor to the same commit as the system. Move Cursor alone with
# `flake-update-cursor` / `nix flake update nixpkgs-cursor`.
#
# Usage: flake-update [checkout]
# The packaged command passes the checkout (lib/machine.nix repoPath).
# Running this file from a checkout with no argument uses that checkout.
set -euo pipefail

if [[ $# -ge 1 && -f "${1}/flake.nix" ]]; then
  root=$1
  shift
else
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if [[ ! -f "$root/flake.nix" ]]; then
  echo "flake-update: checkout not found: $root" >&2
  exit 1
fi
cd "$root"

json="$(curl -fsSL https://api.github.com/repos/UniClipboard/UniClipboard/releases/latest)"
tag="$(printf '%s\n' "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
if [[ -z "$tag" ]]; then
  echo "flake-update: could not parse UniClipboard latest tag" >&2
  exit 1
fi
uc_ver="${tag#v}"
uc_url="https://github.com/UniClipboard/UniClipboard/releases/download/v${uc_ver}/UniClipboard_${uc_ver}_amd64.deb"

chatgpt_ver="$(
  curl -fsSL https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-amd64/Packages |
    awk '/^Package: chatgpt$/{p=1;next} p&&/^Version:/{print $2;exit} p&&/^$/{exit}'
)"
if [[ -z "$chatgpt_ver" ]]; then
  echo "flake-update: could not parse ChatGPT package version" >&2
  exit 1
fi
chatgpt_url="https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${chatgpt_ver}_amd64.deb"

grok_bot_url="$(
  curl -fsSL https://cursor.com/download/bot |
    sed -n 's/.*\(https:\/\/downloads\.cursor\.com\/grokbot\/stable\/[^"]*linux\/x64\/grok-bot_[^"]*_amd64\.deb\).*/\1/p' |
    head -n1
)"
if [[ -z "$grok_bot_url" ]]; then
  echo "flake-update: could not parse Grok Bot amd64 .deb URL" >&2
  exit 1
fi
grok_bot_ver="$(printf '%s\n' "$grok_bot_url" | sed -n 's/.*grok-bot_\([^_]*\)_amd64\.deb/\1/p')"
if [[ -z "$grok_bot_ver" ]]; then
  echo "flake-update: could not parse Grok Bot version from URL" >&2
  exit 1
fi

# NixOS often has no python3 on PATH; prefer it when present, else nixpkgs.
py=(python3)
if ! command -v python3 >/dev/null 2>&1; then
  py=(nix shell nixpkgs#python3 --command python3)
fi
"${py[@]}" - "$root/flake.nix" "$uc_ver" "$uc_url" "$chatgpt_ver" "$chatgpt_url" "$grok_bot_ver" "$grok_bot_url" <<'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
uc_ver, uc_url, chatgpt_ver, chatgpt_url, grok_bot_ver, grok_bot_url = sys.argv[2:8]
text = path.read_text()

replacements = [
    (r'(uniclipboardVersion\s*=\s*")[^"]*(";)', uc_ver, "uniclipboardVersion"),
    (
        r'(uniclipboard-deb\s*=\s*\{[^}]*?url\s*=\s*")[^"]*(")',
        uc_url,
        "uniclipboard-deb url",
    ),
    (r'(chatgptVersion\s*=\s*")[^"]*(";)', chatgpt_ver, "chatgptVersion"),
    (
        r'(chatgpt-deb\s*=\s*\{[^}]*?url\s*=\s*")[^"]*(")',
        chatgpt_url,
        "chatgpt-deb url",
    ),
    (r'(grokBotVersion\s*=\s*")[^"]*(";)', grok_bot_ver, "grokBotVersion"),
    (
        r'(grok-bot-deb\s*=\s*\{[^}]*?url\s*=\s*")[^"]*(")',
        grok_bot_url,
        "grok-bot-deb url",
    ),
]

for pattern, value, label in replacements:
    text, n = re.subn(pattern, rf"\g<1>{value}\2", text, count=1, flags=re.S)
    if n != 1:
        sys.exit(f"flake-update: expected one {label} (got {n})")

old = path.read_text()
if text != old:
    path.write_text(text)
    print(f"UniClipboard → {uc_ver}")
    print(f"ChatGPT → {chatgpt_ver}")
    print(f"Grok Bot → {grok_bot_ver}")
else:
    print(f"UniClipboard already {uc_ver}")
    print(f"ChatGPT already {chatgpt_ver}")
    print(f"Grok Bot already {grok_bot_ver}")
PY

# Every locked root input except nixpkgs-cursor. Listing them (instead of a
# bare `nix flake update`) is what keeps Cursor's nixpkgs pin where it is.
mapfile -t inputs < <(
  "${py[@]}" -c '
import json, sys
root = json.load(sys.stdin)["locks"]["nodes"]["root"]["inputs"]
names = [name for name in sorted(root) if name != "nixpkgs-cursor"]
if not names:
    sys.exit("flake-update: no inputs besides nixpkgs-cursor")
print("\n".join(names))
' < <(nix flake metadata --json)
)
echo "nix flake update ${inputs[*]}"
echo "nixpkgs-cursor は対象外。Cursor だけ上げる: flake-update-cursor"
nix flake update "${inputs[@]}"
echo "flake.lock updated. Review, commit, then rebuild."
