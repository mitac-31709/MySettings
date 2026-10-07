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

  # Curated tuigreet list. tuigreet sorts by Name= (ASCII), not by filename —
  # so we number Names to keep Sway first (Caelestia-AW / Plasma would otherwise win).
  # Hide stock hyprland / plasmax11.
  curatedSessions =
    pkgs.runCommand "mitac-greetd-sessions" { nativeBuildInputs = [ pkgs.gnused ]; }
      ''
        mkdir -p "$out/wayland-sessions"
        if [ -f ${sessionData}/share/wayland-sessions/sway.desktop ]; then
          sed -e 's/^Name=.*/Name=1. Sway/' \
            ${sessionData}/share/wayland-sessions/sway.desktop \
            > "$out/wayland-sessions/sway.desktop"
        fi
        ${lib.concatImapStrings (
          i: s:
          let
            n = i + 1; # 1 = Sway; imap1 starts at 1
          in
          ''
            for desktop in ${s}/share/wayland-sessions/*.desktop; do
              base=$(basename "$desktop")
              sed -e 's/^Name=\(.*\)/Name=${toString n}. \1/' \
                "$desktop" > "$out/wayland-sessions/$base"
            done
          ''
        ) customSessions}
        if [ -f ${sessionData}/share/wayland-sessions/plasma.desktop ]; then
          plasma_n=$((2 + ${toString (builtins.length customSessions)}))
          sed -e "s/^Name=.*/Name=''${plasma_n}. Plasma (Wayland)/" \
            ${sessionData}/share/wayland-sessions/plasma.desktop \
            > "$out/wayland-sessions/plasma.desktop"
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
        # --time uses strftime under LANG=ja_JP.UTF-8 ("2026年 10月 …"), but the
        # greeter TTY has no CJK console glyphs → garbled. Keep digits/ASCII only.
        command = lib.concatStringsSep " " [
          "${lib.getExe pkgs.tuigreet}"
          "--time"
          "--time-format"
          "'%Y-%m-%d %H:%M:%S'"
          "--asterisks"
          "--remember"
          "--remember-session"
          # Fallback when no remembered session (plasma6 would otherwise win via defaultSession).
          "--cmd"
          "sway"
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

  # UniClipboard (and other libsecret apps) need an unlocked Secret Service.
  # KWallet's ksecretd rejects UniClipboard's binary probe; use gnome-keyring.
  # Plasma still gets KWallet via plasma6 → pam on login for native KDE apps.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;

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
