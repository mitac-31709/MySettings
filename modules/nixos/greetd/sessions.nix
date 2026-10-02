# Hyprland session wrappers and .desktop packages for greetd.
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
        export QT_QPA_PLATFORM=wayland
        export QML2_IMPORT_PATH="${config.mitac.hyprland.qmlImportPath}''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
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

  hyprlandCaelestia = mkHyprlandConfWrapper {
    name = "hyprland-caelestia";
    sessionId = "caelestia";
    configName = "caelestia.conf";
  };

  # Prefer aggregated system QML tree (shared with hyprland.nix).
  qmlImportPath = config.mitac.hyprland.qmlImportPath;

  # end4-pC: classic .conf first (PulseAudio + qs). II lua is a last resort —
  # it assumes wpctl/easyeffects and often leaves a broken desktop here.
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
      export QUICKSHELL_CONFIG_NAME=end4-pC
      export QT_QPA_PLATFORM=wayland
      export QML2_IMPORT_PATH="${qmlImportPath}''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"

      log_dir="''${XDG_CACHE_HOME:-$HOME/.cache}"
      mkdir -p "$log_dir"
      log_file="$log_dir/hyprland-startup.log"
      exec >>"$log_file" 2>&1
      printf '[%s] hyprland-startup begin\n' "$(date -Is)"

      hypr_cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
      conf="$hypr_cfg/end4.conf"
      lua="$hypr_cfg/hyprland.lua"

      if [ -f "$conf" ]; then
        printf 'using classic conf: %s\n' "$conf"
        export HYPRLAND_CONFIG="$conf"
        if command -v start-hyprland >/dev/null 2>&1; then
          exec start-hyprland -- --config "$conf"
        fi
        exec Hyprland --config "$conf"
      fi

      if [ -f "$lua" ]; then
        printf 'classic conf missing; falling back to II lua: %s\n' "$lua"
        unset HYPRLAND_CONFIG || true
        exec start-hyprland
      fi

      printf 'missing Hyprland config: need %s or %s\n' "$conf" "$lua"
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
      hyprlandCaelestia
      hyprlandStartup
      hyprlandEnd4
    ];
  };
}
