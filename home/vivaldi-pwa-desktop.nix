# Vivaldi writes PWA .desktop files with an absolute /nix/store/.../vivaldi path.
# After a package update + GC that path disappears and the launcher fails silently.
# Rewrite Exec= to the stable per-user profile symlink (survives store-path churn).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Stable across Vivaldi store hash changes (HM/system profile always refreshed).
  vivaldiBin = "${config.home.profileDirectory}/bin/vivaldi";
  fixScript = pkgs.writeShellApplication {
    name = "vivaldi-pwa-desktop-fix";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      set -euo pipefail
      apps="''${XDG_DATA_HOME:-$HOME/.local/share}/applications"
      target='${vivaldiBin}'
      if [[ ! -e "$target" ]]; then
        echo "vivaldi not at $target" >&2
        exit 0
      fi
      if [[ ! -d "$apps" ]]; then
        exit 0
      fi
      shopt -s nullglob
      fixed=0
      for f in "$apps"/vivaldi-*-*.desktop; do
        # Skip Home Manager–managed symlinks into the store.
        if [[ -L "$f" ]]; then
          continue
        fi
        if ! grep -qE '^Exec=/nix/store/[^ ]*vivaldi' "$f"; then
          continue
        fi
        tmp="$(mktemp)"
        while IFS= read -r line || [[ -n "$line" ]]; do
          case "$line" in
            Exec=/nix/store/*vivaldi*)
              args="''${line#Exec=}"
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
        done <"$f" >"$tmp"
        if ! cmp -s "$f" "$tmp"; then
          mv "$tmp" "$f"
          fixed=$((fixed + 1))
          echo "Fixed PWA desktop: $f"
        else
          rm -f "$tmp"
        fi
      done
      if [[ "$fixed" -eq 0 ]]; then
        echo "Vivaldi PWA desktop files already OK under $apps"
      fi
    '';
  };
in
{
  home.packages = [ fixScript ];

  home.activation.fixVivaldiPwaDesktop = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${fixScript}/bin/vivaldi-pwa-desktop-fix || true
  '';

  # After login: catch Vivaldi rewriting shortcuts while the session was closed.
  systemd.user.services.vivaldi-pwa-desktop-fix = {
    Unit = {
      Description = "Rewrite Vivaldi PWA .desktop Exec paths to current profile";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${fixScript}/bin/vivaldi-pwa-desktop-fix";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
