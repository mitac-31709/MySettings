# Clipboard history picker (cliphist + rofi). Sway / Hyprland bind Super+V.
# Selecting an entry copies it and pastes into the previously focused window.
{ pkgs, lib, ... }:

let
  clipboardHistory = pkgs.writeShellScriptBin "clipboard-history" ''
    set -euo pipefail
    export PATH="${
      lib.makeBinPath [
        pkgs.cliphist
        pkgs.rofi
        pkgs.wl-clipboard
        pkgs.wtype
        pkgs.coreutils
      ]
    }:$PATH"
    sel="$(cliphist list | rofi -dmenu -i -p clipboard || true)"
    if [ -z "''${sel}" ]; then
      exit 0
    fi
    printf '%s\n' "$sel" | cliphist decode | wl-copy
    # Wait for focus to return from rofi, then paste.
    sleep 0.05
    wtype -M ctrl v -m ctrl
  '';
in
{
  home.packages = [ clipboardHistory ];
}
