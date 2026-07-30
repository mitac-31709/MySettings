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
  # Wait for Hyprland's Wayland socket, then start qs if II's hyprland.start
  # did not. Must NOT run qs before WAYLAND_DISPLAY exists — that crashes Qt
  # ("Failed to create wl_display") and leaves a blank desktop.
  waitAndStartQs = ''
    runtime="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    qs_log="''${XDG_CACHE_HOME:-$HOME/.cache}/qs-end4.log"
    i=0
    while [ "$i" -lt 45 ]; do
      for sock in wayland-1 wayland-0; do
        if [ -S "$runtime/$sock" ] && ls "$runtime"/hypr/*/ >/dev/null 2>&1; then
          export WAYLAND_DISPLAY="$sock"
          # Give hyprland.start a moment to spawn qs first.
          sleep 3
          printf '[%s] safety-net: WAYLAND_DISPLAY=%s — ensuring qs\n' "$(date -Is)" "$WAYLAND_DISPLAY"
          # -n: no-op if II already started this config.
          qs -n -c end4-pC >>"$qs_log" 2>&1 &
          return 0
        fi
      done
      i=$((i + 1))
      sleep 1
    done
    printf '[%s] safety-net: no Wayland/Hyprland socket after 45s\n' "$(date -Is)"
  '';

  # QML path for qs under Hyprland (Plasma already injects these).
  # See https://github.com/end-4/dots-hyprland/issues/1750
  qmlImportPath = lib.concatStringsSep ":" [
    "${pkgs.kdePackages.qt5compat}/lib/qt-6/qml"
    "${pkgs.kdePackages.qtpositioning}/lib/qt-6/qml"
    "${pkgs.kdePackages.qtmultimedia}/lib/qt-6/qml"
    "${pkgs.kdePackages.qtimageformats}/lib/qt-6/qml"
  ];

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
      export QML2_IMPORT_PATH="${qmlImportPath}''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"

      log_dir="''${XDG_CACHE_HOME:-$HOME/.cache}"
      mkdir -p "$log_dir"
      log_file="$log_dir/hyprland-startup.log"
      exec >>"$log_file" 2>&1
      printf '[%s] hyprland-startup begin\n' "$(date -Is)"

      hypr_cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
      lua="$hypr_cfg/hyprland.lua"
      conf="$hypr_cfg/end4.conf"

      if [ -f "$lua" ]; then
        printf 'using Illogical Impulse lua via start-hyprland: %s\n' "$lua"
        (${waitAndStartQs}) &
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
      export QML2_IMPORT_PATH="${qmlImportPath}''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"

      log_dir="''${XDG_CACHE_HOME:-$HOME/.cache}"
      mkdir -p "$log_dir"
      log_file="$log_dir/hyprland-startup.log"
      exec >>"$log_file" 2>&1
      printf '[%s] hyprland-end4 begin\n' "$(date -Is)"

      hypr_cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
      lua="$hypr_cfg/hyprland.lua"
      conf="$hypr_cfg/end4.conf"

      if [ -f "$lua" ]; then
        printf 'using Illogical Impulse lua via start-hyprland\n'
        (${waitAndStartQs}) &
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

  # Use /run/current-system paths so tuigreet --remember-session does not keep
  # an old absolute /nix/store/.../hyprland-startup from a previous generation
  # (that still launched Hyprland without start-hyprland / without QML paths).
  caelestiaSession = mkWaylandSession {
    id = "caelestia-aw";
    name = "Caelestia-AW";
    comment = "Hyprland with Caelestia shell (animated wallpapers)";
    exec = "/run/current-system/sw/bin/hyprland-caelestia";
  };

  end4Session = mkWaylandSession {
    id = "end4-pc";
    name = "end4-pC";
    comment = "Hyprland with end4-pC Quickshell (II hyprland-startup)";
    exec = "/run/current-system/sw/bin/hyprland-startup";
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
