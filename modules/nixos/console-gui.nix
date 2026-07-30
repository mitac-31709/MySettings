{ pkgs, ... }:

let
  # Launch a GUI app under cage when no display is available (Console session).
  # If already inside Wayland/X11, run the app as-is.
  gui = pkgs.writeShellApplication {
    name = "gui";
    runtimeInputs = [ pkgs.cage ];
    text = ''
      if [ "$#" -eq 0 ]; then
        printf 'usage: gui <command> [args...]\n' >&2
        exit 1
      fi
      if [ -n "''${WAYLAND_DISPLAY:-}" ] || [ -n "''${DISPLAY:-}" ]; then
        exec "$@"
      fi
      exec cage -s -- "$@"
    '';
  };
in
{
  environment.systemPackages = [
    pkgs.cage
    gui
  ];
}
