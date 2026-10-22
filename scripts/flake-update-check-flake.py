#!/usr/bin/env python3
"""Emit REC lines for outdated GitHub flake inputs (and nixpkgs app hits)."""
from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request

HEADERS = {
    "Accept": "application/vnd.github+json",
    "User-Agent": "flake-update-check",
}

# (id, short, icon, extra path needles beyond pkgs/by-name/xx/id)
WATCH: dict[str, list[tuple[str, str, str, tuple[str, ...]]]] = {
    "nixpkgs": [
        ("ghostty", "gsty", "\uf120", ()),
        ("vivaldi", "viv", "\uf27c", ()),  # distinct from firefox
        ("firefox", "ff", "\uf269", ()),
        ("neovim", "nvim", "\ue62b", ()),
        ("btop", "btop", "\uf080", ()),
        ("yazi", "yazi", "\uf07b", ()),
        ("tmux", "tmux", "\uf489", ()),
        ("peazip", "pea", "\uf1c6", ()),
        ("bottles", "botl", "\uf72f", ()),
        ("discord", "disc", "\uf392", ()),
        ("waybar", "wbar", "\uf2d1", ()),
        ("sway", "sway", "\ue615", ()),
        ("rofi", "rofi", "\uf0c9", ()),
        ("tor-browser", "tor", "\uf06e", ("pkgs/applications/networking/browsers/tor-browser",)),
        ("trayscale", "tsui", "\uf6ff", ()),
        ("onlyoffice-desktopeditors", "oof", "\uf15c", ("onlyoffice",)),
        ("showmethekey", "smtk", "\uf11c", ()),
        ("rquickshare", "qs", "\uf1e0", ()),
        ("aria2", "aria", "\uf019", ()),
        ("yt-dlp", "ytdl", "\uf16a", ()),
        ("bat", "bat", "\uf1c9", ()),
        ("nix-output-monitor", "nom", "\uf1de", ()),
        ("qtscrcpy", "scpy", "\uf10b", ("scrcpy",)),
        ("arduino-cli", "ard", "\uf2db", ()),
    ],
    "nixpkgs-cursor": [
        ("code-cursor", "curs", "\ue795", ()),
        ("cursor-cli", "ccli", "\uf120", ()),
    ],
}

FLAKE_META = {
    "home-manager": ("\uf015", "hm", "home-manager"),
    "affinity-nix": ("\uf1fc", "aff", "affinity-nix"),
    "alsa-ucm-conf-cros": ("\uf028", "alsa", "alsa-ucm-conf-cros"),
}


def http_json(url: str):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=25) as resp:
        return json.load(resp)


def tip_sha(owner: str, repo: str, ref: str) -> str:
    candidates = [
        f"https://api.github.com/repos/{owner}/{repo}/git/ref/heads/{ref}",
        f"https://api.github.com/repos/{owner}/{repo}/git/ref/tags/{ref}",
        f"https://api.github.com/repos/{owner}/{repo}/commits/{ref}",
    ]
    if ref == "HEAD":
        candidates = [f"https://api.github.com/repos/{owner}/{repo}/commits/HEAD"]
    for url in candidates:
        try:
            data = http_json(url)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                continue
            raise
        if "object" in data and isinstance(data["object"], dict):
            sha = data["object"].get("sha") or ""
            if data["object"].get("type") == "tag":
                tdata = http_json(
                    f"https://api.github.com/repos/{owner}/{repo}/git/tags/{sha}"
                )
                return (tdata.get("object") or {}).get("sha") or sha
            return sha
        if "sha" in data:
            return data["sha"] or ""
    return ""


def by_name_dir(attr: str) -> str:
    return f"pkgs/by-name/{attr[:2].lower()}/{attr}"


def content_sha(owner: str, repo: str, path: str, ref: str) -> str | None:
    url = (
        f"https://api.github.com/repos/{owner}/{repo}/contents/{path}"
        f"?ref={ref}"
    )
    try:
        data = http_json(url)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise
    if isinstance(data, list):
        # Directory listing — fingerprint by sorted entry shas.
        return ",".join(sorted(x.get("sha", "") for x in data))
    return data.get("sha")


def package_changed(
    owner: str, repo: str, base: str, head: str, attr: str, extra_needles: tuple[str, ...]
) -> bool:
    paths = [by_name_dir(attr), *extra_needles]
    for path in paths:
        # Prefer directory compare for by-name package trees.
        b = content_sha(owner, repo, path, base)
        h = content_sha(owner, repo, path, head)
        if b is None and h is None:
            continue
        if b != h:
            return True
    return False


def changed_apps_via_compare(owner: str, repo: str, base: str, head: str, watch):
    url = f"https://api.github.com/repos/{owner}/{repo}/compare/{base}...{head}"
    data = http_json(url)
    files = data.get("files") or []
    paths = "\n".join(f.get("filename", "") for f in files).lower()
    hits = []
    for pkg_id, short, icon, needles in watch:
        keys = (pkg_id.lower(), *(n.lower() for n in needles))
        if any(k in paths for k in keys if k):
            hits.append((pkg_id, short, icon))
    truncated = len(files) >= 300
    if data.get("status") in ("ahead", "diverged") and not files:
        truncated = True
    ahead = data.get("ahead_by") or 0
    return hits, truncated, ahead


def changed_apps_via_contents(owner: str, repo: str, base: str, head: str, watch):
    """Per-package contents compare — works when compare file list is truncated."""
    hits = []
    for pkg_id, short, icon, needles in watch:
        try:
            if package_changed(owner, repo, base, head, pkg_id, needles):
                hits.append((pkg_id, short, icon))
        except Exception:
            # Soft-fail one package; keep scanning.
            continue
    return hits


def main() -> int:
    lock = json.load(open(sys.argv[1], encoding="utf-8"))
    nodes = lock["nodes"]
    root_inputs = nodes["root"]["inputs"]

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
        if not tip or tip == rev:
            continue

        if name in WATCH:
            watch = WATCH[name]
            hits: list[tuple[str, str, str]] = []
            truncated = False
            ahead = 0
            try:
                hits, truncated, ahead = changed_apps_via_compare(
                    owner, repo, rev, tip, watch
                )
            except urllib.error.HTTPError as e:
                if e.code == 403:
                    print(f"__FAIL__{name}", flush=True)
                    continue
                truncated = True
            except Exception:
                truncated = True

            # Large nixpkgs deltas omit most files — probe watched apps directly.
            if truncated or (ahead > 50 and len(hits) < 2):
                try:
                    probed = changed_apps_via_contents(owner, repo, rev, tip, watch)
                except urllib.error.HTTPError as e:
                    if e.code == 403:
                        probed = []
                    else:
                        probed = []
                except Exception:
                    probed = []
                seen = {h[0] for h in hits}
                for item in probed:
                    if item[0] not in seen:
                        hits.append(item)
                        seen.add(item[0])

            if hits:
                for pkg_id, short, icon in hits:
                    print(
                        f"REC\t{icon}\t{short}\t{pkg_id} ({name}, +{ahead} commit)",
                        flush=True,
                    )
            else:
                icon, short = ("\uf313", "nix")
                if name == "nixpkgs-cursor":
                    icon, short = ("\ue795", "cur")
                print(
                    f"REC\t{icon}\t{short}\t{name} tip 更新"
                    f"（監視アプリに差分なし / +{ahead} commit）",
                    flush=True,
                )
            continue

        if name in FLAKE_META:
            icon, short, label = FLAKE_META[name]
            print(f"REC\t{icon}\t{short}\t{label} tip 更新", flush=True)
            continue

        print(f"REC\t\uf126\t{name[:4]}\t{name} tip 更新", flush=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
