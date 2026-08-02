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

  # Shared launcher for greetd Hyprland sessions (Caelestia / end4).
  # Prefer start-hyprland (sets compositor env / portals) over raw Hyprland.
  mkHyprlandWrapper =
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
        # Avoid stock hyprland.lua taking over when --config is a classic .conf.
        export HYPRLAND_CONFIG="$conf"
        # Args after -- are forwarded to Hyprland by start-hyprland.
        if command -v start-hyprland >/dev/null 2>&1; then
          exec start-hyprland -- --config "$conf"
        fi
        exec Hyprland --config "$conf"
      '';
    };

  # Console: authenticated TTY login shell (not a Wayland compositor).
  # Listed under wayland-sessions for tuigreet, but clears Wayland/X11 env.
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

  hyprlandCaelestia = mkHyprlandWrapper {
    name = "hyprland-caelestia";
    sessionId = "caelestia";
    configName = "caelestia.conf";
  };

  hyprlandEnd4 = mkHyprlandWrapper {
    name = "hyprland-end4";
    sessionId = "end4";
    configName = "end4.conf";
    extraRuntimeInputs = [ pkgs.quickshell ];
    extraExports = {
      qsConfig = "end4-pC";
      QT_QPA_PLATFORM = "wayland";
      # end4 scripts that still look for the upstream ii name.
      QUICKSHELL_CONFIG_NAME = "end4-pC";
    };
  };

  consoleSession = mkWaylandSession {
    id = "00-console";
    name = "Console";
    comment = "Text console without desktop environment (use: apps / gui <app>)";
    exec = "${consoleWrapper}/bin/mitac-console-session";
    desktopNames = "Console";
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
    comment = "Hyprland with end4-pC Quickshell";
    exec = "${hyprlandEnd4}/bin/hyprland-end4";
  };

  # Sessions we actually support in tuigreet (hide stock hyprland / plasmax11).
  customSessions = [
    consoleSession
    caelestiaSession
    end4Session
  ];

  curatedSessions = pkgs.runCommand "mitac-greetd-sessions" { } ''
    mkdir -p "$out/wayland-sessions" "$out/xsessions"
    ${lib.concatMapStrings (s: ''
      cp -f ${s}/share/wayland-sessions/*.desktop "$out/wayland-sessions/"
    '') customSessions}
    if [ -f ${sessionData}/share/wayland-sessions/plasma.desktop ]; then
      cp -f ${sessionData}/share/wayland-sessions/plasma.desktop "$out/wayland-sessions/"
    fi
    # Intentionally leave xsessions empty (no plasmax11).
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
          "--xsessions"
          "${curatedSessions}/xsessions"
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

  # greetd already substasks login PAM (KWallet via Plasma); keep explicit.
  security.pam.services.greetd.kwallet.enable = true;

  services.displayManager.sessionPackages = customSessions;

  # Wrappers on PATH for manual starts from an existing shell.
  environment.systemPackages = [
    consoleWrapper
    hyprlandCaelestia
    hyprlandEnd4
  ];
}
