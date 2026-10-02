#!/usr/bin/env bash
# Bump UniClipboard release URL (versioned assets) then `nix flake update`
# so Cursor (nixpkgs-cursor), Send Anywhere (rolling .deb), and UniClipboard
# all refresh in one shot.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

json="$(curl -fsSL https://api.github.com/repos/UniClipboard/UniClipboard/releases/latest)"
tag="$(printf '%s\n' "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
if [[ -z "$tag" ]]; then
  echo "flake-update: could not parse UniClipboard latest tag" >&2
  exit 1
fi
ver="${tag#v}"
url="https://github.com/UniClipboard/UniClipboard/releases/download/v${ver}/UniClipboard_${ver}_amd64.deb"

python3 - "$root/flake.nix" "$ver" "$url" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
ver, url = sys.argv[2], sys.argv[3]
text = path.read_text()
text2, n1 = re.subn(
    r'(uniclipboardVersion\s*=\s*")[^"]*(";)',
    rf"\g<1>{ver}\2",
    text,
    count=1,
)
text3, n2 = re.subn(
    r'(uniclipboard-deb\s*=\s*\{[^}]*?url\s*=\s*")[^"]*(")',
    rf"\g<1>{url}\2",
    text2,
    count=1,
    flags=re.S,
)
if n1 != 1 or n2 != 1:
    sys.exit(f"flake-update: expected one uniclipboardVersion and one uniclipboard-deb url (got {n1}, {n2})")
if text3 != text:
    path.write_text(text3)
    print(f"UniClipboard → {ver}")
else:
    print(f"UniClipboard already {ver}")
PY

nix flake update
echo "flake.lock updated. Review, commit, then rebuild."
