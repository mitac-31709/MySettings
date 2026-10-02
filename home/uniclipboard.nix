# UniClipboard: sync clipboard with Windows (and other devices).
# Pair once in the GUI (`uniclipboard`); uniclipd keeps syncing in the background.
{ pkgs, ... }:

let
  uniclipboard = pkgs.callPackage ../pkgs/uniclipboard { };
in
{
  # Also listed in programs.nix; package here so the service path is explicit.
  home.packages = [ uniclipboard ];

  systemd.user.services.uniclipd = {
    Unit = {
      Description = "UniClipboard sync daemon";
      After = [ "graphical-session.target" ];
      BindsTo = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${uniclipboard}/bin/uniclipd";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
