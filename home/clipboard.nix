# Clipboard history picker (cliphist + rofi). Sway / Hyprland bind Super+V.
{ pkgs, lib, ... }:

let
  clipboardHistory = pkgs.writeShellScriptBin "clipboard-history" ''
    set -euo pipefail
    export PATH="${
      lib.makeBinPath [
        pkgs.cliphist
        pkgs.rofi
        pkgs.wl-clipboard
        pkgs.coreutils
      ]
    }:$PATH"
    sel="$(cliphist list | rofi -dmenu -i -p clipboard || true)"
    if [ -z "''${sel}" ]; then
      exit 0
    fi
    printf '%s\n' "$sel" | cliphist decode | wl-copy
  '';
in
{
  home.packages = [ clipboardHistory ];
}
