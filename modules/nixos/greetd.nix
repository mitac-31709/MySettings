{
  config,
  pkgs,
  lib,
  ...
}:

let
  sessionData = config.services.displayManager.sessionData.desktops;

  mkWaylandSession =
    {
      id,
      name,
      comment,
      exec,
      desktopNames ? "Hyprland",
    }:
    let
      desktop = pkgs.writeText "${id}.desktop" ''
        [Desktop Entry]
        Name=${name}
        Comment=${comment}
        Exec=${exec}
        Type=Application
        DesktopNames=${desktopNames}
      '';
    in
    pkgs.runCommand "${id}-session"
      {
        passthru.providedSessions = [ id ];
      }
      ''
        mkdir -p "$out/share/wayland-sessions"
        cp ${desktop} "$out/share/wayland-sessions/${id}.desktop"
      '';

  # Console: no compositor — login shell on the VT. Use `gui <app>` for kiosk GUI.
  consoleSession = mkWaylandSession {
    id = "00-console";
    name = "Console";
    comment = "Text console without desktop environment (use: apps / gui <app>)";
    exec = "${pkgs.bashInteractive}/bin/bash -l";
    desktopNames = "Console";
  };

  hyprlandCaelestia = pkgs.writeShellApplication {
    name = "hyprland-caelestia";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.systemd
    ];
    text = ''
      export XDG_CURRENT_DESKTOP=Hyprland
      export XDG_SESSION_DESKTOP=Hyprland
      export XDG_SESSION_TYPE=wayland
      export MITAC_SESSION=caelestia
      conf="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr/caelestia.conf"
      if [ ! -f "$conf" ]; then
        printf 'missing Hyprland config: %s\n' "$conf" >&2
        exit 1
      fi
      # Avoid stock hyprland.lua taking over when --config is a classic .conf.
      export HYPRLAND_CONFIG="$conf"
      exec Hyprland --config "$conf"
    '';
  };

  # end4-pC needs Illogical Impulse's hyprland.lua (hl.on("hyprland.start", …)
  # starts qs, hypridle, clipboard, …). Launch via start-hyprland so that file
  # is used — not a minimal .conf that skips the II startup path.
  #
  # Fall back to end4.conf if lua is missing (older HM generations / partial sync).
  hyprlandStartup = pkgs.writeShellApplication {
    name = "hyprland-startup";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.quickshell
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      export XDG_CURRENT_DESKTOP=Hyprland
      export XDG_SESSION_DESKTOP=Hyprland
      export XDG_SESSION_TYPE=wayland
      export MITAC_SESSION=end4
      export qsConfig=end4-pC
      export QT_QPA_PLATFORM=wayland

      log_dir="''${XDG_CACHE_HOME:-$HOME/.cache}"
      mkdir -p "$log_dir"
      log_file="$log_dir/hyprland-startup.log"
      exec >>"$log_file" 2>&1
      printf '[%s] hyprland-startup begin\n' "$(date -Is)"

      hypr_cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
      lua="$hypr_cfg/hyprland.lua"
      conf="$hypr_cfg/end4.conf"

      if [ -f "$lua" ]; then
        printf 'using Illogical Impulse lua: %s\n' "$lua"
        unset HYPRLAND_CONFIG || true
        exec start-hyprland
      fi

      if [ -f "$conf" ]; then
        printf 'lua missing; falling back to classic conf: %s\n' "$conf"
        export HYPRLAND_CONFIG="$conf"
        exec Hyprland --config "$conf"
      fi

      printf 'missing both %s and %s\n' "$lua" "$conf"
      exit 1
    '';
  };

  # Stable name used by older greetd session .desktop files. Prefer II startup,
  # else classic end4.conf (greetd does not restart on switch by design).
  hyprlandEnd4 = pkgs.writeShellApplication {
    name = "hyprland-end4";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.quickshell
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      export XDG_CURRENT_DESKTOP=Hyprland
      export XDG_SESSION_DESKTOP=Hyprland
      export XDG_SESSION_TYPE=wayland
      export MITAC_SESSION=end4
      export qsConfig=end4-pC
      export QT_QPA_PLATFORM=wayland

      log_dir="''${XDG_CACHE_HOME:-$HOME/.cache}"
      mkdir -p "$log_dir"
      log_file="$log_dir/hyprland-startup.log"
      exec >>"$log_file" 2>&1
      printf '[%s] hyprland-end4 begin\n' "$(date -Is)"

      hypr_cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
      lua="$hypr_cfg/hyprland.lua"
      conf="$hypr_cfg/end4.conf"

      if [ -f "$lua" ] && command -v start-hyprland >/dev/null; then
        printf 'using Illogical Impulse lua via start-hyprland\n'
        unset HYPRLAND_CONFIG || true
        exec start-hyprland
      fi

      if [ -f "$conf" ]; then
        printf 'using classic conf: %s\n' "$conf"
        export HYPRLAND_CONFIG="$conf"
        exec Hyprland --config "$conf"
      fi

      printf 'missing Hyprland config: need %s or %s\n' "$lua" "$conf"
      exit 1
    '';
  };

  caelestiaSession = mkWaylandSession {
    id = "caelestia-aw";
    name = "Caelestia-AW";
    comment = "Hyprland with Caelestia shell (animated wallpapers)";
    exec = "${hyprlandCaelestia}/bin/hyprland-caelestia";
  };

  end4Session = mkWaylandSession {
    id = "end4-pc";
    name = "end4-pC";
    comment = "Hyprland with end4-pC Quickshell (II hyprland-startup)";
    exec = "${hyprlandStartup}/bin/hyprland-startup";
  };

  # Only expose the sessions we support — hide stock hyprland / hyprland-uwsm
  # (autogenerated hyprland.lua expects kitty and confuses tuigreet).
  # No X11 sessions: Plasma (X11) / startx are intentionally dropped.
  curatedSessions = pkgs.runCommand "mitac-greetd-sessions" { } ''
    mkdir -p "$out/wayland-sessions"
    for f in \
      ${consoleSession}/share/wayland-sessions/*.desktop \
      ${caelestiaSession}/share/wayland-sessions/*.desktop \
      ${end4Session}/share/wayland-sessions/*.desktop
    do
      cp -f "$f" "$out/wayland-sessions/"
    done
    # Plasma / GNOME Wayland only
    if [ -f ${sessionData}/share/wayland-sessions/plasma.desktop ]; then
      cp -f ${sessionData}/share/wayland-sessions/plasma.desktop "$out/wayland-sessions/"
    fi
    if [ -f ${sessionData}/share/wayland-sessions/gnome.desktop ]; then
      cp -f ${sessionData}/share/wayland-sessions/gnome.desktop "$out/wayland-sessions/"
    fi
  '';
in
{
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        user = "greeter";
        command = lib.concatStringsSep " " [
          "${lib.getExe pkgs.tuigreet}"
          "--time"
          "--asterisks"
          "--remember"
          "--remember-session"
          "--user-menu"
          "--sessions"
          "${curatedSessions}/wayland-sessions"
        ];
      };
    };
  };

  # Suppress boot spam on the greeter TTY.
  systemd.services.greetd.serviceConfig = {
    Type = "idle";
    StandardInput = "tty";
    StandardOutput = "tty";
    StandardError = "journal";
    TTYReset = true;
    TTYVHangup = true;
    TTYVTDisallocate = true;
  };

  services.displayManager.sessionPackages = [
    consoleSession
    caelestiaSession
    end4Session
  ];

  # Wrappers on PATH for manual starts from an existing shell.
  environment.systemPackages = [
    hyprlandCaelestia
    hyprlandStartup
    hyprlandEnd4
  ];
}
