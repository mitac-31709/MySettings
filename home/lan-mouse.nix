# Lan Mouse: receive mouse/keyboard from a Windows server (software KVM).
# Windows holds the physical input; this host emulates pointer/keyboard on Sway/etc.
#
# This home-manager pin has no programs.lan-mouse module, so there is no
# declarative settings block to fill in. Fingerprints and the peer address
# come from the Windows PC; they are not written here.
#
# First-time pairing (once both sides run lan-mouse):
# 1. Windows: winget install lan-mouse → Add this host (Tailscale name/IP) as a client.
# 2. Here: run `lan-mouse` (GUI), Authorize the Windows fingerprint under Incoming.
# 3. Optional: persist via ~/.config/lan-mouse/config.toml (authorized_fingerprints).
{ pkgs, ... }:

{
  home.packages = [ pkgs.lan-mouse ];

  systemd.user.services.lan-mouse = {
    Unit = {
      Description = "Lan Mouse (receive input from Windows)";
      After = [ "graphical-session.target" ];
      BindsTo = [ "graphical-session.target" ];
      StartLimitIntervalSec = 30;
      StartLimitBurst = 3;
    };
    Service = {
      ExecStart = "${pkgs.lan-mouse}/bin/lan-mouse daemon";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
