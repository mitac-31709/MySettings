#!/usr/bin/env python3
"""Sync imperative NetworkManager Wi-Fi profiles into secrets/nm-connections.age.

Merges existing profiles from decrypted nm-connections.age (falling back to
/run/agenix/nm-connections) with local *.nmconnection files in
/etc/NetworkManager/system-connections so multi-host profiles (e.g. Chromebook +
VAIO) are preserved while CLI/TUI additions (nmcli/nmtui) are saved cleanly.
Skips rewriting nm-connections.age when normalized profiles are unchanged.
"""

from __future__ import annotations

import argparse
import configparser
import fcntl
import os
import pathlib
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass

HEADER_RE = re.compile(r"^\s*#\s*===\s*(.+?)\s*===\s*$")
STRIP_PREFIXES_WRITE = ("interface-name=", "mac-address=", "timestamp=")
STRIP_PREFIXES_CMP = ("interface-name=", "mac-address=", "timestamp=")
WIFI_TYPES = {"wifi", "802-11-wireless"}


@dataclass
class ProfileEntry:
    name: str
    raw_body: str
    ctype: str
    uuid: str
    cid: str
    ssid: str

    @property
    def ctype_norm(self) -> str:
        return "wifi" if self.ctype in WIFI_TYPES else self.ctype

    @property
    def signature(self) -> tuple[tuple[str, tuple[tuple[str, str], ...]], ...]:
        cleaned = clean_keyfile(self.raw_body, drop_prefixes=STRIP_PREFIXES_CMP)
        cp = configparser.ConfigParser(interpolation=None)
        cp.optionxform = str
        try:
            cp.read_string(cleaned)
        except configparser.Error:
            return (("__raw__", (("__text__", cleaned.strip()),)),)
        sections = []
        for sec in sorted(cp.sections()):
            items = tuple(sorted((k, v) for k, v in cp.items(sec)))
            sections.append((sec, items))
        return tuple(sections)


def clean_keyfile(text: str, drop_prefixes: tuple[str, ...]) -> str:
    """Remove host-specific/volatile keyfile lines while keeping formatting."""
    out = []
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith(drop_prefixes):
            continue
        out.append(line)
    content = "".join(out).strip()
    return (content + "\n") if content else ""


def parse_nm_metadata(name: str, body: str) -> ProfileEntry:
    cp = configparser.ConfigParser(interpolation=None)
    cp.optionxform = str
    ctype = ""
    uuid = ""
    cid = ""
    ssid = ""
    try:
        cp.read_string(body)
        ctype = cp.get("connection", "type", fallback="").strip()
        uuid = cp.get("connection", "uuid", fallback="").strip()
        cid = cp.get("connection", "id", fallback="").strip()
        ssid = cp.get("wifi", "ssid", fallback="").strip()
    except configparser.Error:
        pass
    return ProfileEntry(
        name=name,
        raw_body=body.strip() + "\n" if body.strip() else "",
        ctype=ctype,
        uuid=uuid,
        cid=cid,
        ssid=ssid,
    )


def parse_bundle(raw: str) -> list[ProfileEntry]:
    sections: list[tuple[str | None, str]] = []
    cur_name: str | None = None
    cur_lines: list[str] = []
    for line in raw.splitlines(keepends=True):
        m = HEADER_RE.match(line)
        if m:
            if cur_lines:
                sections.append((cur_name, "".join(cur_lines)))
            cur_name = m.group(1).strip()
            cur_lines = []
        else:
            cur_lines.append(line)
    if cur_lines:
        sections.append((cur_name, "".join(cur_lines)))

    if not sections and "[connection]" in raw:
        sections = [("default", raw)]

    entries: list[ProfileEntry] = []
    for idx, (name, body) in enumerate(sections, start=1):
        if "[connection]" not in body:
            continue
        entries.append(parse_nm_metadata(name or f"profile-{idx}.nmconnection", body))
    return entries


def read_pubkeys(pubkey_file: pathlib.Path) -> list[str]:
    if not pubkey_file.is_file():
        return []
    keys = []
    for line in pubkey_file.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s and not s.startswith("#"):
            keys.append(s)
    return keys


def read_existing_bundle(
    age_file: pathlib.Path,
    master_key: pathlib.Path,
    fallback_decrypted: pathlib.Path,
) -> tuple[bool, str]:
    """Return (exists, raw_plaintext) or raise RuntimeError if locked/unreadable."""
    if not age_file.is_file():
        return False, ""

    if master_key.is_file() and os.access(master_key, os.R_OK):
        res = subprocess.run(
            ["age", "-d", "-i", str(master_key), str(age_file)],
            capture_output=True,
            text=True,
            check=False,
        )
        if res.returncode == 0:
            return True, res.stdout
        raise RuntimeError(
            f"failed to decrypt {age_file} with {master_key}: {res.stderr.strip()}"
        )

    if fallback_decrypted.is_file() and os.access(fallback_decrypted, os.R_OK):
        return True, fallback_decrypted.read_text(encoding="utf-8")

    raise RuntimeError(
        f"{age_file} exists, but neither {master_key} nor {fallback_decrypted} is readable"
    )


def load_local_profiles(nm_dir: pathlib.Path, include_all: bool) -> list[ProfileEntry]:
    if not nm_dir.is_dir():
        return []
    profiles: list[ProfileEntry] = []
    for path in sorted(nm_dir.glob("*.nmconnection")):
        if not path.is_file():
            continue
        raw = path.read_text(encoding="utf-8", errors="replace")
        if "[connection]" not in raw:
            continue
        cleaned = clean_keyfile(raw, drop_prefixes=STRIP_PREFIXES_WRITE)
        entry = parse_nm_metadata(path.name, cleaned)
        if not include_all and entry.ctype not in WIFI_TYPES:
            continue
        profiles.append(entry)
    return profiles


def find_matching_index(entries: list[ProfileEntry], candidate: ProfileEntry) -> int | None:
    if candidate.uuid:
        for idx, item in enumerate(entries):
            if item.uuid and item.uuid == candidate.uuid:
                return idx
    if candidate.cid:
        for idx, item in enumerate(entries):
            if (
                item.ctype_norm == candidate.ctype_norm
                and item.cid == candidate.cid
                and item.ssid == candidate.ssid
            ):
                return idx
    return None


def merge_profiles(
    existing: list[ProfileEntry],
    local: list[ProfileEntry],
) -> tuple[list[ProfileEntry], bool]:
    merged = list(existing)
    changed = False
    for loc in local:
        idx = find_matching_index(merged, loc)
        if idx is None:
            merged.append(loc)
            changed = True
        else:
            prev = merged[idx]
            if prev.signature != loc.signature:
                # Keep original header name if already named sensibly.
                merged[idx] = ProfileEntry(
                    name=prev.name or loc.name,
                    raw_body=loc.raw_body,
                    ctype=loc.ctype,
                    uuid=loc.uuid or prev.uuid,
                    cid=loc.cid,
                    ssid=loc.ssid,
                )
                changed = True
    return merged, changed


def render_bundle(entries: list[ProfileEntry]) -> str:
    parts = [f"# === {e.name} ===\n{e.raw_body.strip()}\n" for e in entries]
    return "\n".join(parts)


def write_encrypted_bundle(
    plaintext: str,
    dest: pathlib.Path,
    recipients: list[str],
) -> None:
    cmd = ["age", "-e"]
    for r in recipients:
        cmd.extend(["-r", r])

    res = subprocess.run(
        cmd,
        input=plaintext.encode("utf-8"),
        capture_output=True,
        check=False,
    )
    if res.returncode != 0:
        raise RuntimeError(f"age encryption failed: {res.stderr.decode(errors='replace').strip()}")

    parent_stat = dest.parent.stat()
    fd, tmp_name = tempfile.mkstemp(dir=str(dest.parent), prefix=f".{dest.name}.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(res.stdout)
        os.chmod(tmp_name, 0o644)
        if os.geteuid() == 0:
            os.chown(tmp_name, parent_stat.st_uid, parent_stat.st_gid)
        os.replace(tmp_name, dest)
    except Exception:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)
        raise


def acquire_lock(lock_path: pathlib.Path):
    target = lock_path
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        fh = open(target, "a+", encoding="utf-8")
    except OSError:
        fallback = pathlib.Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / lock_path.name
        fh = open(fallback, "a+", encoding="utf-8")
    fcntl.flock(fh.fileno(), fcntl.LOCK_EX)
    return fh


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Sync local NM Wi-Fi profiles to agenix")
    parser.add_argument("--secrets-dir", type=pathlib.Path, required=True)
    parser.add_argument(
        "--nm-dir",
        type=pathlib.Path,
        default=pathlib.Path("/etc/NetworkManager/system-connections"),
    )
    parser.add_argument(
        "--master-key",
        type=pathlib.Path,
        default=pathlib.Path("/etc/agenix/master.key"),
    )
    parser.add_argument(
        "--fallback-decrypted",
        type=pathlib.Path,
        default=pathlib.Path("/run/agenix/nm-connections"),
    )
    parser.add_argument(
        "--lock-file",
        type=pathlib.Path,
        default=pathlib.Path("/run/nm-agenix-sync.lock"),
    )
    parser.add_argument("--include-all", action="store_true")
    parser.add_argument("--skip-if-locked", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    pubkeys = read_pubkeys(args.secrets_dir / "master-pubkey.txt")
    if not pubkeys:
        print(
            f"nm-agenix-sync: 公開鍵が見つからないためスキップします ({args.secrets_dir / 'master-pubkey.txt'})",
            file=sys.stderr,
        )
        return 0 if args.skip_if_locked else 1

    age_file = args.secrets_dir / "nm-connections.age"
    lock_fh = acquire_lock(args.lock_file)
    try:
        try:
            exists, existing_raw = read_existing_bundle(
                age_file=age_file,
                master_key=args.master_key,
                fallback_decrypted=args.fallback_decrypted,
            )
        except RuntimeError as exc:
            if args.skip_if_locked:
                print(f"nm-agenix-sync: スキップ ({exc})", file=sys.stderr)
                return 0
            print(f"エラー: {exc}", file=sys.stderr)
            return 1

        existing_entries = parse_bundle(existing_raw) if exists else []
        local_entries = load_local_profiles(args.nm_dir, include_all=args.include_all)
        if not local_entries:
            print("nm-agenix-sync: 同期対象のローカル Wi-Fi プロファイルはありません。")
            return 0

        merged, changed = merge_profiles(existing_entries, local_entries)
        if not changed:
            print("nm-agenix-sync: 変更なし（secrets/nm-connections.age は最新です）。")
            return 0

        if args.dry_run:
            print(
                f"nm-agenix-sync: 更新予定 (合計 {len(merged)} 件のプロファイル / {age_file})"
            )
            return 0

        bundle_text = render_bundle(merged)
        write_encrypted_bundle(bundle_text, age_file, pubkeys)
        print(
            f"nm-agenix-sync: 更新完了 ({len(merged)} 件のプロファイルを {age_file} へ暗号化保存しました)。"
        )
        return 0
    finally:
        fcntl.flock(lock_fh.fileno(), fcntl.LOCK_UN)
        lock_fh.close()


if __name__ == "__main__":
    raise SystemExit(main())
