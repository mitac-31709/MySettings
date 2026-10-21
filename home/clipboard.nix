# Clipboard history picker (cliphist + rofi). Sway binds Super+V.
# Selecting an entry copies it and pastes into the previously focused window.
# Store watchers run as user systemd units under every graphical session.
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

  mkCliphistWatcher = name: pasteArgs: {
    Unit = {
      Description = "cliphist store (${name})";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste ${pasteArgs} --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
      RestartSec = 1;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
in
{
  home.packages = [
    clipboardHistory
    pkgs.cliphist
    pkgs.wtype
  ];

  systemd.user.services.cliphist-text = mkCliphistWatcher "text" "--type text";
  systemd.user.services.cliphist-image = mkCliphistWatcher "image" "--type image";
}
