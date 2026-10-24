# Vivaldi ignores chrome.sidePanel.setOptions (VB-120826). The ChatGPT
# extension's manifest default_path is an empty loading stub, and the real UI
# is only switched in via setOptions — so the side panel stays blank white.
# Keep a patched unpacked copy (static default_path → work sidepanel) and
# refresh it when the Chrome Web Store install updates.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  extId = "hehggadaopoacecdllhhajmbjkdcmajg";
  patchScript = pkgs.writeShellApplication {
    name = "vivaldi-chatgpt-extension-patch";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.jq
      pkgs.rsync
    ];
    text = ''
      set -euo pipefail
      ext_id='${extId}'
      dest="''${XDG_DATA_HOME:-$HOME/.local/share}/vivaldi-chatgpt-extension"
      src_root="$HOME/.config/vivaldi/Default/Extensions/$ext_id"
      if [[ ! -d "$src_root" ]]; then
        echo "ChatGPT extension not installed under $src_root" >&2
        exit 0
      fi
      src="$(find "$src_root" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n1)"
      if [[ -z "$src" || ! -f "$src/manifest.json" ]]; then
        echo "No ChatGPT extension version dir in $src_root" >&2
        exit 0
      fi
      mkdir -p "$dest"
      rsync -a --delete --exclude=_metadata "$src/" "$dest/"
      tmp="$(mktemp)"
      jq '
        .side_panel.default_path = "codex-work-sidepanel.html"
        | del(.update_url)
      ' "$dest/manifest.json" >"$tmp"
      mv "$tmp" "$dest/manifest.json"
      rm -rf "$dest/_metadata"
      echo "Patched ChatGPT extension for Vivaldi → $dest"
      echo "  version: $(jq -r .version "$dest/manifest.json")"
      echo "  side_panel.default_path: $(jq -r .side_panel.default_path "$dest/manifest.json")"
    '';
  };
in
{
  home.packages = [ patchScript ];

  home.activation.patchVivaldiChatgptExtension = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${patchScript}/bin/vivaldi-chatgpt-extension-patch || true
  '';

  # One-shot after login so a Web Store auto-update while Vivaldi was closed
  # still gets re-patched before the side panel is opened.
  systemd.user.services.vivaldi-chatgpt-extension-patch = {
    Unit = {
      Description = "Patch ChatGPT extension for Vivaldi side panel";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${patchScript}/bin/vivaldi-chatgpt-extension-patch";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
