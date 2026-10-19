# Screen-edge frame + banner while ChatGPT Computer Use is active.
# Detects ~/.codex/node_repl/active_execs and the sky_linux helper process.
{ pkgs, ... }:

{
  home.packages = [ pkgs.chatgpt-cua-indicator ];

  systemd.user.services.chatgpt-cua-indicator = {
    Unit = {
      Description = "ChatGPT Computer Use on-screen indicator";
      After = [ "graphical-session.target" ];
      BindsTo = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.chatgpt-cua-indicator}/bin/chatgpt-cua-indicator";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
