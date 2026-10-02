# UniClipboard: sync clipboard with Windows (and other devices).
# Pair once in the GUI (`uniclipboard`); uniclipd keeps syncing in the background.
#
# uniclipd must remain an unwrapped binary named exactly `uniclipd` — the GUI
# rejects Nix makeWrapper names (`.uniclipd-wrapped`) as a mismatched daemon.
#
# Needs an unlocked org.freedesktop.secrets (gnome-keyring). KWallet's ksecretd
# rejects UniClipboard's binary integrity probe.
{ pkgs, ... }:

{
  home.packages = [
    pkgs.uniclipboard
    pkgs.seahorse # unlock Default Keyring when PAM did not (engine 1223)
  ];

  # Start secrets component for this user session (PAM also unlocks at login).
  services.gnome-keyring = {
    enable = true;
    components = [ "secrets" ];
  };

  systemd.user.services.uniclipd = {
    Unit = {
      Description = "UniClipboard sync daemon";
      After = [ "graphical-session.target" ];
      BindsTo = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.uniclipboard}/bin/uniclipd";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
