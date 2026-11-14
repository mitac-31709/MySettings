# Declarative defaults/overrides for Cursor IDE writable JSON files.
# Keeps ~/.config/Cursor/User/settings.json and ~/.cursor/argv.json writable so
# in-app Settings changes work without EROFS, while reproducing declared keys.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cursorSettings = {
    "window.autoDetectColorScheme" = false;
    "cursor.composer.usageSummaryDisplay" = "always";
    "cursor.composer.queueManualSendBehavior2" = "steer";
    "cursor.composer.shouldChimeAfterChatFinishes" = true;
    "remote.SSH.remotePlatform" = {
      "172.18.43.172" = "linux";
    };
    "[typst]" = {
      "editor.wordWrap" = "on";
      "editor.formatOnSave" = true;
      "editor.defaultFormatter" = "myriad-dreamin.tinymist";
    };
    "tinymist.exportPdf" = "onSave";
    "tinymist.formatterMode" = "typstyle";
    "tinymist.systemFonts" = true;
  };

  cursorArgv = {
    "password-store" = "basic";
  };

  syncScript = pkgs.writeShellApplication {
    name = "cursor-sync-declared-config";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      settings_file="''${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User/settings.json"
      argv_file="$HOME/.cursor/argv.json"
      python3 - \
        "$settings_file" \
        '${builtins.toJSON cursorSettings}' \
        "$argv_file" \
        '${builtins.toJSON cursorArgv}' <<'PY'
      import json
      import os
      import sys
      import tempfile
      from pathlib import Path


      def strip_jsonc(text: str) -> str:
          """Strip // and /* */ comments plus trailing commas outside strings."""
          out = []
          i = 0
          n = len(text)
          in_str = False
          while i < n:
              c = text[i]
              if in_str:
                  out.append(c)
                  if c == "\\" and i + 1 < n:
                      out.append(text[i + 1])
                      i += 2
                      continue
                  if c == '"':
                      in_str = False
                  i += 1
              elif c == '"':
                  in_str = True
                  out.append(c)
                  i += 1
              elif c == "/" and i + 1 < n and text[i + 1] == "/":
                  i += 2
                  while i < n and text[i] not in "\r\n":
                      i += 1
              elif c == "/" and i + 1 < n and text[i + 1] == "*":
                  i += 2
                  while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                      i += 1
                  i += 2
              else:
                  out.append(c)
                  i += 1

          no_comments = "".join(out)
          res = []
          i = 0
          n = len(no_comments)
          in_str = False
          while i < n:
              c = no_comments[i]
              if in_str:
                  res.append(c)
                  if c == "\\" and i + 1 < n:
                      res.append(no_comments[i + 1])
                      i += 2
                      continue
                  if c == '"':
                      in_str = False
                  i += 1
              elif c == '"':
                  in_str = True
                  res.append(c)
                  i += 1
              elif c == ",":
                  j = i + 1
                  while j < n and no_comments[j] in " \t\r\n":
                      j += 1
                  if j < n and no_comments[j] in "}]":
                      i += 1
                      continue
                  res.append(c)
                  i += 1
              else:
                  res.append(c)
                  i += 1
          return "".join(res)


      def deep_merge(base: dict, overlay: dict) -> dict:
          merged = dict(base)
          for k, v in overlay.items():
              if isinstance(v, dict) and isinstance(merged.get(k), dict):
                  merged[k] = deep_merge(merged[k], v)
              else:
                  merged[k] = v
          return merged


      def sync_file(path: Path, overlay: dict) -> None:
          if path.is_symlink():
              return
          existing: dict = {}
          if path.is_file():
              raw = path.read_text(encoding="utf-8")
              cleaned = strip_jsonc(raw).strip()
              if cleaned:
                  existing = json.loads(cleaned)
          merged = deep_merge(existing, overlay)
          if path.is_file() and merged == existing:
              return
          path.parent.mkdir(parents=True, exist_ok=True)
          fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.")
          try:
              with os.fdopen(fd, "w", encoding="utf-8") as fh:
                  fh.write(json.dumps(merged, indent=4, ensure_ascii=False) + "\n")
              os.chmod(tmp, 0o600)
              os.replace(tmp, path)
          except Exception:
              os.unlink(tmp)
              raise


      pairs = [(Path(sys.argv[1]), json.loads(sys.argv[2])), (Path(sys.argv[3]), json.loads(sys.argv[4]))]
      for path, overlay in pairs:
          sync_file(path, overlay)
      PY
    '';
  };
in
{
  home.activation.syncCursorConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${syncScript}/bin/cursor-sync-declared-config || true
  '';
}
