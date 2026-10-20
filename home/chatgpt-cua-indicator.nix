# Screen-edge frame + banner + chat panel while an agent drives the screen.
# ChatGPT: ~/.codex active_execs / sky_linux. Cursor: recent browser tool_use.
{ pkgs, ... }:

{
  home.packages = [ pkgs.chatgpt-cua-indicator ];

  systemd.user.services.chatgpt-cua-indicator = {
    Unit = {
      Description = "Agent screen HUD (ChatGPT / Cursor browser control)";
      After = [ "graphical-session.target" ];
      BindsTo = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.chatgpt-cua-indicator}/bin/chatgpt-cua-indicator";
      # swaymsg / wtype / pkill for mode switch and agent-screen-stop.
      Environment = [
        "PATH=${pkgs.sway}/bin:${pkgs.wtype}/bin:${pkgs.procps}/bin:%h/.nix-profile/bin:/run/current-system/sw/bin"
      ];
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
