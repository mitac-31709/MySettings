# greetd + tuigreet: login greeter and curated session list.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  sessionData = config.services.displayManager.sessionData.desktops;
  customSessions = config.mitac.greetd.customSessions;

  # Curated tuigreet list: hide stock hyprland / plasmax11; include DE Wayland sessions.
  curatedSessions = pkgs.runCommand "mitac-greetd-sessions" { } ''
    mkdir -p "$out/wayland-sessions"
    ${lib.concatMapStrings (s: ''
      cp -f ${s}/share/wayland-sessions/*.desktop "$out/wayland-sessions/"
    '') customSessions}
    if [ -f ${sessionData}/share/wayland-sessions/plasma.desktop ]; then
      cp -f ${sessionData}/share/wayland-sessions/plasma.desktop "$out/wayland-sessions/"
    fi
    if [ -f ${sessionData}/share/wayland-sessions/gnome.desktop ]; then
      cp -f ${sessionData}/share/wayland-sessions/gnome.desktop "$out/wayland-sessions/"
    fi
    if [ -f ${sessionData}/share/wayland-sessions/xfce-wayland.desktop ]; then
      cp -f ${sessionData}/share/wayland-sessions/xfce-wayland.desktop "$out/wayland-sessions/"
    fi
    if [ -f ${sessionData}/share/wayland-sessions/sway.desktop ]; then
      cp -f ${sessionData}/share/wayland-sessions/sway.desktop "$out/wayland-sessions/"
    fi
  '';
in
{
  imports = [ ./greetd/sessions.nix ];

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

  systemd.services.greetd.serviceConfig = {
    Type = "idle";
    StandardInput = "tty";
    StandardOutput = "tty";
    StandardError = "journal";
    TTYReset = true;
    TTYVHangup = true;
    TTYVTDisallocate = true;
  };

  security.pam.services.greetd.kwallet.enable = true;
}
