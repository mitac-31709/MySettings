# RQuickShare writes ~/.config/autostart/RQuickShare.desktop with a hardcoded
# /nix/store/... path that breaks after upgrades/GC. Rewrite Exec= to the
# stable per-user profile symlink (same approach as vivaldi-pwa-desktop.nix).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  rquickshareBin = "${config.home.profileDirectory}/bin/rquickshare";
  fixScript = pkgs.writeShellApplication {
    name = "rquickshare-desktop-fix";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      set -euo pipefail
      autostart="''${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
      desktop="$autostart/RQuickShare.desktop"
      target='${rquickshareBin}'
      if [[ ! -e "$target" || -L "$desktop" || ! -f "$desktop" ]]; then
        exit 0
      fi
      if ! grep -qE '^Exec=/nix/store/[^ ]*rquickshare' "$desktop"; then
        exit 0
      fi
      tmp="$(mktemp)"
      while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
          Exec=/nix/store/*rquickshare*)
            args="''${line#Exec=}"
            args="''${args%"''${args##*[![:space:]]}"}"
            rest="''${args#* }"
            if [[ "$args" == "$rest" ]]; then
              printf 'Exec=%s\n' "$target"
            else
              printf 'Exec=%s %s\n' "$target" "$rest"
            fi
            ;;
          *)
            printf '%s\n' "$line"
            ;;
        esac
      done <"$desktop" >"$tmp"
      if ! cmp -s "$desktop" "$tmp"; then
        mv "$tmp" "$desktop"
        echo "Fixed RQuickShare autostart desktop: $desktop"
      else
        rm -f "$tmp"
      fi
    '';
  };
in
{
  home.activation.fixRQuickShareDesktop = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${fixScript}/bin/rquickshare-desktop-fix || true
  '';

  systemd.user.services.rquickshare-desktop-fix = {
    Unit = {
      Description = "Rewrite RQuickShare autostart .desktop Exec path to current profile";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${fixScript}/bin/rquickshare-desktop-fix";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
