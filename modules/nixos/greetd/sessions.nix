# Console / Hyprland session wrappers and .desktop packages for greetd.
{
  config,
  pkgs,
  lib,
  ...
}:

let
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

  # Shared launcher for classic-.conf Hyprland sessions (Caelestia).
  mkHyprlandConfWrapper =
    {
      name,
      sessionId,
      configName,
      extraExports ? { },
      extraRuntimeInputs ? [ ],
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.hyprland
        pkgs.systemd
        pkgs.dbus
      ]
      ++ extraRuntimeInputs;
      text = ''
        export XDG_CURRENT_DESKTOP=Hyprland
        export XDG_SESSION_DESKTOP=Hyprland
        export XDG_SESSION_TYPE=wayland
        export MITAC_SESSION=${lib.escapeShellArg sessionId}
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") extraExports
        )}
        conf="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr/${configName}"
        if [ ! -f "$conf" ]; then
          printf 'missing Hyprland config: %s\n' "$conf" >&2
          exit 1
        fi
        # Avoid stock/II hyprland.lua taking over when --config is a classic .conf.
        export HYPRLAND_CONFIG="$conf"
        if command -v start-hyprland >/dev/null 2>&1; then
          exec start-hyprland -- --config "$conf"
        fi
        exec Hyprland --config "$conf"
      '';
    };

  # Console: authenticated TTY login shell (not a Wayland compositor).
  consoleWrapper = pkgs.writeShellApplication {
    name = "mitac-console-session";
    runtimeInputs = [ pkgs.bashInteractive ];
    text = ''
      export XDG_SESSION_TYPE=tty
      export XDG_CURRENT_DESKTOP=Console
      export XDG_SESSION_DESKTOP=Console
      unset WAYLAND_DISPLAY DISPLAY
      exec ${pkgs.bashInteractive}/bin/bash -l
    '';
  };

  hyprlandCaelestia = mkHyprlandConfWrapper {
    name = "hyprland-caelestia";
    sessionId = "caelestia";
    configName = "caelestia.conf";
  };

  # Prefer aggregated system QML tree (shared with hyprland.nix).
  qmlImportPath = config.mitac.hyprland.qmlImportPath;

  # Wait for Hyprland's Wayland socket, then start qs if II's hyprland.start
  # did not. Must NOT run qs before WAYLAND_DISPLAY exists — that crashes Qt.
  waitAndStartQs = ''
    runtime="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    qs_log="''${XDG_CACHE_HOME:-$HOME/.cache}/qs-end4.log"
    i=0
    while [ "$i" -lt 45 ]; do
      for sock in wayland-1 wayland-0; do
        if [ -S "$runtime/$sock" ] && ls "$runtime"/hypr/*/ >/dev/null 2>&1; then
          export WAYLAND_DISPLAY="$sock"
          sleep 3
          printf '[%s] safety-net: WAYLAND_DISPLAY=%s — ensuring qs\n' "$(date -Is)" "$WAYLAND_DISPLAY"
          qs -n -c end4-pC >>"$qs_log" 2>&1 &
          exit 0
        fi
      done
      i=$((i + 1))
      sleep 1
    done
    printf '[%s] safety-net: no Wayland/Hyprland socket after 45s\n' "$(date -Is)"
  '';

  # end4-pC: Illogical Impulse hyprland.lua via start-hyprland; fall back to end4.conf.
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

      printf 'missing Hyprland config: need %s or %s\n' "$lua" "$conf"
      exit 1
    '';
  };

  # Stable name used by older greetd session .desktop files.
  hyprlandEnd4 = pkgs.writeShellApplication {
    name = "hyprland-end4";
    runtimeInputs = [ ];
    text = ''
      exec ${hyprlandStartup}/bin/hyprland-startup "$@"
    '';
  };

  consoleSession = mkWaylandSession {
    id = "00-console";
    name = "Console";
    comment = "Text console without desktop environment (use: apps / gui <app>)";
    exec = "${consoleWrapper}/bin/mitac-console-session";
    desktopNames = "Console";
  };

  # Use /run/current-system paths so tuigreet --remember-session does not keep
  # an old absolute /nix/store/... wrapper from a previous generation.
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

  customSessions = [
    consoleSession
    caelestiaSession
    end4Session
  ];
in
{
  options.mitac.greetd.customSessions = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    internal = true;
    description = "Custom wayland-session packages for the curated tuigreet list.";
  };

  config = {
    mitac.greetd.customSessions = customSessions;

    services.displayManager.sessionPackages = customSessions;

    environment.systemPackages = [
      consoleWrapper
      hyprlandCaelestia
      hyprlandStartup
      hyprlandEnd4
    ];
  };
}
