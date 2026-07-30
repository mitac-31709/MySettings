{
  config,
  pkgs,
  lib,
  ...
}:

let
  sessionsDir = "${config.services.displayManager.sessionData.desktops}/share";

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
    comment = "Text console without desktop environment (use: gui <app>)";
    exec = "${pkgs.bashInteractive}/bin/bash -l";
    desktopNames = "Console";
  };

  hyprlandCaelestia = pkgs.writeShellApplication {
    name = "hyprland-caelestia";
    runtimeInputs = [ pkgs.hyprland ];
    text = ''
      export XDG_CURRENT_DESKTOP=Hyprland
      export XDG_SESSION_TYPE=wayland
      export MITAC_SESSION=caelestia
      conf="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr/caelestia.conf"
      if [ ! -f "$conf" ]; then
        printf 'missing Hyprland config: %s\n' "$conf" >&2
        exit 1
      fi
      exec Hyprland --config "$conf"
    '';
  };

  hyprlandEnd4 = pkgs.writeShellApplication {
    name = "hyprland-end4";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.quickshell
    ];
    text = ''
      export XDG_CURRENT_DESKTOP=Hyprland
      export XDG_SESSION_TYPE=wayland
      export MITAC_SESSION=end4
      export qsConfig=end4-pC
      conf="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr/end4.conf"
      if [ ! -f "$conf" ]; then
        printf 'missing Hyprland config: %s\n' "$conf" >&2
        exit 1
      fi
      exec Hyprland --config "$conf"
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
    comment = "Hyprland with end4-pC Quickshell";
    exec = "${hyprlandEnd4}/bin/hyprland-end4";
  };
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
          "${sessionsDir}/wayland-sessions"
          "--xsessions"
          "${sessionsDir}/xsessions"
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
    hyprlandEnd4
  ];
}
