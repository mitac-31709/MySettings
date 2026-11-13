# Left-edge AI status chips: hover Waybar AI column → slide-in chips;
# click a chip for expanded detail; trailing chip toggles completion sound
# (Windows Me startup). Reads $XDG_RUNTIME_DIR/ai-status-agents.json
# written by waybar-ai-status (store script). Prefs: ~/.config/ai-status/prefs.json
{ pkgs, ... }:

{
  home.packages = [ pkgs.ai-status-chips ];

  systemd.user.services.ai-status-chips = {
    Unit = {
      Description = "AI status hover chips (Waybar companion)";
      After = [
        "graphical-session.target"
        "waybar.service"
      ];
      BindsTo = [ "graphical-session.target" ];
      # Waybar publishes agent JSON; start even if waybar unit naming differs.
      Wants = [ "waybar.service" ];
      StartLimitIntervalSec = 30;
      StartLimitBurst = 3;
    };
    Service = {
      ExecStart = "${pkgs.ai-status-chips}/bin/ai-status-chips";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
