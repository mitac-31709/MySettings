# Lan Mouse: receive mouse/keyboard from a Windows server (software KVM).
# Windows holds the physical input; this host emulates pointer/keyboard on Sway/etc.
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
