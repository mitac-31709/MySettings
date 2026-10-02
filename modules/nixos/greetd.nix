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

  # Curated tuigreet list: Sway first, then Hyprland customs, then DE Wayland.
  # Hide stock hyprland / plasmax11; stock sway is renamed to 00-sway for sort order.
  curatedSessions = pkgs.runCommand "mitac-greetd-sessions" { } ''
    mkdir -p "$out/wayland-sessions"
    if [ -f ${sessionData}/share/wayland-sessions/sway.desktop ]; then
      cp -f ${sessionData}/share/wayland-sessions/sway.desktop "$out/wayland-sessions/00-sway.desktop"
    fi
    ${lib.concatMapStrings (s: ''
      cp -f ${s}/share/wayland-sessions/*.desktop "$out/wayland-sessions/"
    '') customSessions}
    if [ -f ${sessionData}/share/wayland-sessions/plasma.desktop ]; then
      cp -f ${sessionData}/share/wayland-sessions/plasma.desktop "$out/wayland-sessions/"
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

  # NumLock on before tuigreet (and as the default for new VTs).
  # Compositors that reset LED state still need their own session option.
  systemd.services.numLockOnTty = {
    description = "Enable NumLock on TTYs";
    wantedBy = [ "multi-user.target" ];
    before = [ "greetd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "numLockOnTty" ''
        for tty in /dev/tty{1..6}; do
          ${pkgs.kbd}/bin/setleds -D +num < "$tty" || true
        done
      '';
    };
  };
}
