# Repair Vivaldi Web Store extensions when Default/Extensions is missing but
# Preferences (+ optionally extensions_crx_cache) remain — typical after an old
# restic restore that excluded the Extensions tree.
{
  pkgs,
  ...
}:

let
  chatgptExtId = "hehggadaopoacecdllhhajmbjkdcmajg";
  repairScript = pkgs.writeShellApplication {
    name = "vivaldi-extensions-repair";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.python3
    ];
    text = ''
      set -euo pipefail
      export CHATGPT_EXT_ID='${chatgptExtId}'
      # Quit Vivaldi first if the user left it running (Preferences overwrite).
      if pgrep -x vivaldi-bin >/dev/null 2>&1; then
        echo "Vivaldi is running; quit it first, then re-run." >&2
        exit 1
      fi
      python3 - <<'PY'
      import hashlib, io, json, os, shutil, subprocess, zipfile
      from pathlib import Path

      home = Path.home()
      cache = home / ".config/vivaldi/extensions_crx_cache"
      ext_root = home / ".config/vivaldi/Default/Extensions"
      pref_path = home / ".config/vivaldi/Default/Preferences"
      patched = home / ".local/share/vivaldi-chatgpt-extension"
      chatgpt_id = os.environ["CHATGPT_EXT_ID"]
      prod = "131.0.0.0"

      if not pref_path.is_file():
          print(f"No Vivaldi Preferences at {pref_path}", flush=True)
          raise SystemExit(0)

      pref = json.loads(pref_path.read_text(encoding="utf-8"))
      settings = pref.setdefault("extensions", {}).setdefault("settings", {})
      cache.mkdir(parents=True, exist_ok=True)
      meta_path = cache / "metadata.json"
      meta = {"hashes": {}}
      if meta_path.is_file():
          try:
              meta = json.loads(meta_path.read_text(encoding="utf-8"))
              meta.setdefault("hashes", {})
          except json.JSONDecodeError:
              meta = {"hashes": {}}

      def unzip_crx_bytes(data: bytes, dest: Path) -> dict:
          idx = data.find(b"PK\x03\x04")
          if idx < 0:
              raise RuntimeError("no zip payload in CRX")
          if dest.exists():
              shutil.rmtree(dest)
          dest.mkdir(parents=True, exist_ok=True)
          with zipfile.ZipFile(io.BytesIO(data[idx:])) as z:
              z.extractall(dest)
              return json.loads(z.read("manifest.json"))

      def install_crx(eid: str, data: bytes, preferred_rel: str | None) -> str:
          digest = hashlib.sha256(data).hexdigest()
          crx_file = cache / digest
          if not crx_file.exists():
              crx_file.write_bytes(data)
          meta["hashes"][digest] = {"appid": eid}
          idx = data.find(b"PK\x03\x04")
          man = json.loads(zipfile.ZipFile(io.BytesIO(data[idx:])).read("manifest.json"))
          ver = man.get("version", "0")
          rel = preferred_rel if preferred_rel and preferred_rel.startswith(f"{eid}/") else f"{eid}/{ver}_0"
          # If version in preferred path mismatches CRX, prefer actual version dir.
          if not preferred_rel or preferred_rel != f"{eid}/{ver}_0":
              rel = f"{eid}/{ver}_0"
          dest = ext_root / rel
          unzip_crx_bytes(data, dest)
          ent = settings.get(eid)
          if isinstance(ent, dict):
              ent["path"] = rel
              if isinstance(ent.get("manifest"), dict):
                  ent["manifest"]["version"] = ver
          return rel

      restored = 0
      # 1) Local CRX cache
      for digest, info in sorted((meta.get("hashes") or {}).items()):
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
          dest = ext_root / rel if isinstance(rel, str) and rel and not rel.startswith("/") else None
          if dest is not None and dest.is_dir() and (dest / "manifest.json").is_file():
              print(f"ok  {eid} (cache, already present)", flush=True)
              continue
          rel = install_crx(eid, crx.read_bytes(), rel if isinstance(rel, str) else None)
          restored += 1
          print(f"fix {eid} → {rel} (cache)", flush=True)

      # 2) Chrome Web Store for remaining Preferences paths
      missing = []
      for eid, ent in settings.items():
          if not isinstance(ent, dict):
              continue
          path = ent.get("path")
          if not isinstance(path, str) or not path or path.startswith("/"):
              continue
          if not (ext_root / path).exists():
              missing.append((eid, path, (ent.get("manifest") or {}).get("name", eid)))

      for eid, rel, name in missing:
          url = (
              "https://clients2.google.com/service/update2/crx"
              f"?response=redirect&prodversion={prod}&acceptformat=crx3"
              f"&x=id%3D{eid}%26installsource%3Dondemand%26uc"
          )
          print(f"fetch {name} ({eid}) …", end=" ", flush=True)
          tmp = cache / f".fetch-{eid}.crx"
          r = subprocess.run(
              ["curl", "-fsSL", "-L", "--max-time", "120", "-o", str(tmp), url],
              capture_output=True,
              text=True,
          )
          if r.returncode != 0 or not tmp.is_file() or tmp.stat().st_size < 1000:
              print(f"FAIL ({(r.stderr or '''').strip() or 'empty'})", flush=True)
              tmp.unlink(missing_ok=True)
              continue
          data = tmp.read_bytes()
          tmp.unlink(missing_ok=True)
          try:
              out_rel = install_crx(eid, data, rel)
          except Exception as exc:
              print(f"FAIL ({exc})", flush=True)
              continue
          restored += 1
          print(f"OK → {out_rel}", flush=True)

      # 3) Patched ChatGPT side-panel copy
      if patched.is_dir() and (patched / "manifest.json").is_file():
          man = json.loads((patched / "manifest.json").read_text(encoding="utf-8"))
          man.setdefault("side_panel", {})["default_path"] = "codex-work-sidepanel.html"
          man.pop("update_url", None)
          ver = man.get("version", "0")
          rel = f"{chatgpt_id}/{ver}_0"
          dest = ext_root / rel
          if dest.exists():
              shutil.rmtree(dest)
          shutil.copytree(patched, dest)
          (dest / "manifest.json").write_text(
              json.dumps(man, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
          )
          entry = settings.get(chatgpt_id)
          if not isinstance(entry, dict) or not entry:
              entry = {
                  "account_extension_type": 0,
                  "active_permissions": {
                      "api": man.get("permissions", []),
                      "explicit_host": man.get("host_permissions", []),
                      "manifest_permissions": man.get("permissions", []),
                      "scriptable_host": [],
                  },
                  "commands": {},
                  "content_settings": [],
                  "creation_flags": 1,
                  "disable_reasons": [],
                  "from_webstore": False,
                  "granted_permissions": {
                      "api": man.get("permissions", []),
                      "explicit_host": man.get("host_permissions", []),
                      "manifest_permissions": man.get("permissions", []),
                      "scriptable_host": [],
                  },
                  "incognito_content_settings": [],
                  "incognito_preferences": {},
                  "location": 1,
                  "preferences": {},
                  "regular_only_preferences": {},
                  "was_installed_by_default": False,
                  "was_installed_by_oem": False,
                  "withholding_permissions": False,
              }
          entry["manifest"] = man
          entry["path"] = rel
          entry["location"] = 1
          entry["from_webstore"] = False
          entry["disable_reasons"] = []
          settings[chatgpt_id] = entry
          restored += 1
          print(f"fix {chatgpt_id} → {rel} (patched ChatGPT)", flush=True)

      pref_path.write_text(
          json.dumps(pref, ensure_ascii=False, separators=(",", ":")),
          encoding="utf-8",
      )
      meta_path.write_text(
          json.dumps(meta, ensure_ascii=False, separators=(",", ":")),
          encoding="utf-8",
      )
      print(f"Restored/updated {restored} extension tree(s) under {ext_root}", flush=True)
      PY
    '';
  };
in
{
  home.packages = [ repairScript ];
}
