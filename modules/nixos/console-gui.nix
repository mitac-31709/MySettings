{ pkgs, ... }:

let
  appsAwk = pkgs.writeText "apps-desktop.awk" ''
    function flush(    n, e, typ, term) {
      if (file == "") return
      typ = (Type == "" ? "Application" : Type)
      if (typ != "Application") return
      if (tolower(Hidden) == "true") return
      if (tolower(NoDisplay) == "true") return
      if (Name == "" || Exec == "") return

      n = Name
      if (lang != "" && NameLang[lang] != "") n = NameLang[lang]

      e = Exec
      # Strip desktop Exec field codes.
      gsub(/%(f|F|u|U|d|D|n|N|i|c|k|v|m)/, "", e)
      gsub(/%%/, "%", e)
      gsub(/[ \t]+/, " ", e)
      sub(/^[ \t]+/, "", e)
      sub(/[ \t]+$/, "", e)
      if (e == "") return

      term = (tolower(Terminal) == "true") ? "term" : "gui"
      gsub(/[ \t]+/, " ", n)
      printf "%s\t%s\t%s\n", n, term, e
    }
    BEGINFILE {
      file = FILENAME
      Name = ""; Exec = ""; Type = ""; Hidden = ""; NoDisplay = ""; Terminal = ""
      delete NameLang
      in_entry = 0
    }
    ENDFILE { flush() }
    /^\[/ {
      if ($0 == "[Desktop Entry]") {
        in_entry = 1
      } else if (in_entry) {
        flush()
        in_entry = 0
        Name = ""; Exec = ""; Type = ""; Hidden = ""; NoDisplay = ""; Terminal = ""
        delete NameLang
      }
      next
    }
    !in_entry { next }
    /^Name\[/ {
      key = $0
      sub(/^=.*/, "", key)
      sub(/^Name\[/, "", key)
      sub(/\]$/, "", key)
      val = $0
      sub(/^[^=]*=/, "", val)
      NameLang[key] = val
      next
    }
    /^Name=/ { sub(/^[^=]*=/, ""); Name = $0; next }
    /^Exec=/ { sub(/^[^=]*=/, ""); Exec = $0; next }
    /^Type=/ { sub(/^[^=]*=/, ""); Type = $0; next }
    /^Hidden=/ { sub(/^[^=]*=/, ""); Hidden = $0; next }
    /^NoDisplay=/ { sub(/^[^=]*=/, ""); NoDisplay = $0; next }
    /^Terminal=/ { sub(/^[^=]*=/, ""); Terminal = $0; next }
  '';

  # Launch a GUI app under cage when no display is available (Console session).
  # If already inside Wayland/X11, run the app as-is.
  gui = pkgs.writeShellApplication {
    name = "gui";
    runtimeInputs = [ pkgs.cage ];
    text = ''
      if [ "$#" -eq 0 ]; then
        if command -v apps >/dev/null 2>&1; then
          exec apps
        fi
        printf 'usage: gui <command> [args...]\n' >&2
        printf '       apps          # list / pick installed applications\n' >&2
        exit 1
      fi
      if [ -n "''${WAYLAND_DISPLAY:-}" ] || [ -n "''${DISPLAY:-}" ]; then
        exec "$@"
      fi
      exec cage -s -- "$@"
    '';
  };

  # TTY-friendly application browser: list .desktop apps and optionally launch
  # via `gui` (cage on Console, passthrough when a display is already up).
  apps = pkgs.writeShellApplication {
    name = "apps";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.fzf
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = ''
            set -euo pipefail

            usage() {
              cat >&2 <<'EOF'
      usage: apps [-l|--list] [-h|--help] [query...]

        Interactive application list for Console (and any TTY).
        Pick an entry to launch it with `gui` (cage when no display).

        -l, --list   print Name / command and exit (no fzf)
        -h, --help   show this help

        With query words, pre-filter the list (also used as fzf query).
      EOF
            }

            list_only=0
            query=()
            while [ "$#" -gt 0 ]; do
              case "$1" in
                -l|--list)
                  list_only=1
                  shift
                  ;;
                -h|--help)
                  usage
                  exit 0
                  ;;
                --)
                  shift
                  query+=("$@")
                  break
                  ;;
                -*)
                  printf 'unknown option: %s\n' "$1" >&2
                  usage
                  exit 1
                  ;;
                *)
                  query+=("$1")
                  shift
                  ;;
              esac
            done

            # Prefer ja Name[] when locale is Japanese.
            lang_prefix="''${LANG%%.*}"
            lang_prefix="''${lang_prefix%%_*}"
            if [ -z "$lang_prefix" ]; then
              lang_prefix=en
            fi

      data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"
      data_dirs="''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

      # Collect unique basenames (earlier XDG dirs win).
      # Avoid changing IFS globally — it breaks find/-name and path handling.
      # Follow symlinks (-L): NixOS profiles expose .desktop files as symlinks.
      declare -A seen=()
      desktop_files=()
      roots=("''${data_home}")
      IFS=':' read -r -a data_dir_arr <<< "$data_dirs"
      roots+=("''${data_dir_arr[@]}")
      for root in "''${roots[@]}"; do
        [ -n "$root" ] || continue
        appdir="$root/applications"
        [ -d "$appdir" ] || continue
        while IFS= read -r f; do
          [ -n "$f" ] || continue
          base="''${f##*/}"
          if [ -n "''${seen[$base]+x}" ]; then
            continue
          fi
          seen[$base]=1
          desktop_files+=("$f")
        done < <(find -L "$appdir" -type f -name '*.desktop' 2>/dev/null | LC_ALL=C sort)
      done

      if [ "''${#desktop_files[@]}" -eq 0 ]; then
        printf 'no .desktop applications found\n' >&2
        exit 1
      fi

            catalog="$(
              gawk -v lang="$lang_prefix" -f ${appsAwk} "''${desktop_files[@]}"
            )"

            if [ -z "$catalog" ]; then
              printf 'no launchable applications found\n' >&2
              exit 1
            fi

            catalog="$(printf '%s\n' "$catalog" | LC_ALL=C sort -t $'\t' -k1,1 -u)"

            filter_q=""
            if [ "''${#query[@]}" -gt 0 ]; then
              filter_q="''${query[*]}"
            fi

            if [ "$list_only" -eq 1 ]; then
              if [ -n "$filter_q" ]; then
                printf '%s\n' "$catalog" | gawk -F '\t' -v q="$filter_q" '
                  BEGIN { split(tolower(q), words, /[ \t]+/) }
                  {
                    line = tolower($0)
                    ok = 1
                    for (i in words) {
                      if (words[i] != "" && index(line, words[i]) == 0) ok = 0
                    }
                    if (ok) printf "%-40s  %s\n", $1, $3
                  }
                '
              else
                printf '%s\n' "$catalog" | gawk -F '\t' '{ printf "%-40s  %s\n", $1, $3 }'
              fi
              exit 0
            fi

            if [ ! -t 0 ] || [ ! -t 1 ]; then
              printf 'apps: interactive mode needs a TTY; use: apps --list\n' >&2
              exit 1
            fi

            fzf_args=(--prompt='apps> ' --height=80% --reverse --info=inline)
            if [ -n "$filter_q" ]; then
              fzf_args+=(--query="$filter_q")
            fi

            selection="$(
              printf '%s\n' "$catalog" | gawk -F '\t' '{ printf "%-40s  [%s]  %s\n", $1, $2, $3 }' |
                fzf "''${fzf_args[@]}"
            )" || exit 1

            [ -n "$selection" ] || exit 1

            mode="$(printf '%s\n' "$selection" | gawk 'match($0, /\[(gui|term)\]/, a) { print a[1]; exit }')"
            cmd="$(printf '%s\n' "$selection" | gawk '{
              if (match($0, /\[(gui|term)\][ \t]+(.*)$/, a)) { print a[2]; exit }
            }')"

      if [ -z "$cmd" ]; then
        printf 'failed to parse selection\n' >&2
        exit 1
      fi

      # Word-split Exec= from .desktop (field codes already stripped).
      # shellcheck disable=SC2206
      cmd_args=($cmd)

      if [ "$mode" = "term" ]; then
        exec "''${cmd_args[@]}"
      fi
      if command -v gui >/dev/null 2>&1; then
        exec gui "''${cmd_args[@]}"
      fi
      exec "''${cmd_args[@]}"
    '';
  };
in
{
  environment.systemPackages = [
    pkgs.cage
    gui
    apps
  ];
}
