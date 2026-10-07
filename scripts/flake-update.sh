#!/usr/bin/env bash
# Bump versioned .deb URLs then `nix flake update` so Cursor (nixpkgs-cursor),
# Send Anywhere (rolling .deb), UniClipboard, and ChatGPT desktop all refresh.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

python3 - "$root/flake.nix" "$uc_ver" "$uc_url" "$chatgpt_ver" "$chatgpt_url" <<'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
uc_ver, uc_url, chatgpt_ver, chatgpt_url = sys.argv[2:6]
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
else:
    print(f"UniClipboard already {uc_ver}")
    print(f"ChatGPT already {chatgpt_ver}")
PY

nix flake update
echo "flake.lock updated. Review, commit, then rebuild."
