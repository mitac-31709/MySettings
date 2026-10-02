# UniClipboard: sync clipboard with Windows (and other devices).
# Pair once in the GUI (`uniclipboard`); uniclipd keeps syncing in the background.
#
# uniclipd must remain an unwrapped binary named exactly `uniclipd` — the GUI
# rejects Nix makeWrapper names (`.uniclipd-wrapped`) as a mismatched daemon.
{ pkgs, ... }:

{
  home.packages = [ pkgs.uniclipboard ];

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
