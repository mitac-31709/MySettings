# Lan Mouse: receive mouse/keyboard from a Windows server (software KVM).
# Windows holds the physical input; this host emulates pointer/keyboard on Sway/etc.
#
# This home-manager pin has no programs.lan-mouse module, and runtime pairing
# writes both ~/.config/lan-mouse/config.toml (authorized_fingerprints) and
# private lan-mouse.pem (kept in backup; scrubbed on --new-device).
# Activation ensures the known authorized fingerprint is present while keeping
# config.toml writable for adding peers in the GUI.
#
# First-time pairing (once both sides run lan-mouse):
# 1. Windows: winget install lan-mouse → Add this host (Tailscale name/IP) as a client.
# 2. Here: run `lan-mouse` (GUI), Authorize the Windows fingerprint under Incoming.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  authorizedFingerprints = {
    "58:9e:ec:3b:cb:fe:9c:f5:9c:77:1b:f4:3f:5e:4a:cc:22:a8:7c:73:77:78:cc:b6:d7:a7:cb:5b:46:1b:56:81" =
      "galleria-mitac";
  };

  ensureScript = pkgs.writeShellApplication {
    name = "lan-mouse-ensure-fingerprints";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/lan-mouse/config.toml"
      desired='${builtins.toJSON authorizedFingerprints}'
      python3 - "$cfg" "$desired" <<'PY'
      import json
      import os
      import re
      import sys
      import tempfile
      from pathlib import Path

      cfg_path = Path(sys.argv[1])
      desired = json.loads(sys.argv[2])
      text = cfg_path.read_text(encoding="utf-8") if cfg_path.is_file() else ""
      lines = text.splitlines()

      section_re = re.compile(r"^\s*\[([^\]]+)\]\s*(?:#.*)?$")
      key_re = re.compile(r'^\s*"([^"]+)"\s*=')

      existing = set()
      section_start = None
      section_end = len(lines)
      cur_section = None
      for idx, line in enumerate(lines):
          m = section_re.match(line)
          if m:
              if cur_section == "authorized_fingerprints":
                  section_end = idx
              cur_section = m.group(1).strip()
              if cur_section == "authorized_fingerprints" and section_start is None:
                  section_start = idx
              continue
          if cur_section == "authorized_fingerprints":
              km = key_re.match(line)
              if km:
                  existing.add(km.group(1))

      missing = [f'"{fp}" = "{name}"' for fp, name in desired.items() if fp not in existing]
      if not missing:
          raise SystemExit(0)

      if section_start is None:
          if lines and lines[-1].strip():
              lines.append("")
          lines.append("[authorized_fingerprints]")
          lines.extend(missing)
      else:
          lines = lines[:section_end] + missing + lines[section_end:]

      new_text = "\n".join(lines) + "\n"
      cfg_path.parent.mkdir(parents=True, exist_ok=True)
      fd, tmp = tempfile.mkstemp(dir=str(cfg_path.parent), prefix=".config.toml.")
      try:
          with os.fdopen(fd, "w", encoding="utf-8") as fh:
              fh.write(new_text)
          os.chmod(tmp, 0o600)
          os.replace(tmp, cfg_path)
      except Exception:
          os.unlink(tmp)
          raise
      PY
    '';
  };
in
{
  home.packages = [ pkgs.lan-mouse ];

  home.activation.ensureLanMouseAuthorizedFingerprints = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${ensureScript}/bin/lan-mouse-ensure-fingerprints || true
  '';

  systemd.user.services.lan-mouse = {
    Unit = {
      Description = "Lan Mouse (receive input from Windows)";
      After = [ "graphical-session.target" ];
      BindsTo = [ "graphical-session.target" ];
      StartLimitIntervalSec = 30;
      StartLimitBurst = 3;
    };
    Service = {
      ExecStart = "${pkgs.lan-mouse}/bin/lan-mouse daemon";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
