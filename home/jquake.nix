# JQuake: login autostart, tray background, alert fullscreen over swaylock.
#
# - Patches a few Settings.properties keys on each start (tray / always-on-top /
#   wake screen / no window until alert) without rewriting the whole file.
# - Sway needs xembedsniproxy so Java AWT SystemTray.isSupported() is true
#   (waybar speaks SNI; AWT speaks XEmbed).
# - ext-session-lock blocks normal windows above swaylock; on alert we dismiss
#   swaylock and fullscreen the map (intentional emergency unlock).
{
  pkgs,
  lib,
  config,
  ...
}:

let
  confDir = "${config.home.homeDirectory}/Library/Application Support/JQuake";
  propsFile = "${confDir}/Settings.properties";

  jquakeClass = "net-jquake-app-Main";
  swayCriteria = ''[class="^${jquakeClass}$"]'';

  xembedsniproxyBin = "${pkgs.kdePackages.plasma-workspace}/bin/xembedsniproxy";

  jquakeAutostart = pkgs.writeShellApplication {
    name = "jquake-autostart";
    runtimeInputs = [
      pkgs.jquake
      pkgs.gnused
      pkgs.gnugrep
      pkgs.coreutils
      pkgs.procps
    ];
    text = ''
      mkdir -p ${lib.escapeShellArg confDir}
      props=${lib.escapeShellArg propsFile}

      set_prop() {
        local key="$1" val="$2"
        if [[ -f "$props" ]] && grep -q "^''${key}=" "$props"; then
          sed -i "s|^''${key}=.*|''${key}=''${val}|" "$props"
        else
          printf '%s=%s\n' "$key" "$val" >>"$props"
        fi
      }

      # Tray/window: icon + minimize-on-close (stay resident in background).
      set_prop winChoice 2
      # Alerts: raise above other windows; wake DPMS; do not suppress pops.
      set_prop alwaysOnTop true
      set_prop wakeUpScreen true
      set_prop gameMode false
      set_prop persistentMode true
      # Start in tray; popEEW / popShindo / … open the window on events.
      set_prop openOnStartup false

      # Sway: wait for xembedsniproxy so AWT SystemTray.isSupported() is true.
      if [[ "''${XDG_CURRENT_DESKTOP:-}" == "sway" ]]; then
        for _ in $(seq 1 40); do
          if pgrep -x xembedsniproxy >/dev/null 2>&1; then
            break
          fi
          sleep 0.25
        done
      fi

      exec JQuake "$@"
    '';
  };

  jquakeSwayAlert = pkgs.writeShellApplication {
    name = "jquake-sway-alert";
    runtimeInputs = [
      pkgs.jq
      pkgs.sway
      pkgs.procps
      pkgs.coreutils
    ];
    text = ''
      criteria=${lib.escapeShellArg swayCriteria}

      raise_alert() {
        # Wake outputs (pairs with JQuake wakeUpScreen).
        swaymsg 'output * power on' >/dev/null 2>&1 || true
        # Session lock sits above all app surfaces; dismiss so the map is visible.
        if pgrep -x swaylock >/dev/null 2>&1; then
          pkill -x swaylock || true
        fi
        swaymsg "$criteria fullscreen enable, sticky enable, focus" >/dev/null 2>&1 || true
      }

      is_jquake_event() {
        jq -e --arg class ${lib.escapeShellArg jquakeClass} '
          (.change == "new" or .change == "urgent" or .change == "fullscreen_mode")
          and (.container.window_properties.class? == $class)
        ' >/dev/null 2>&1
      }

      swaymsg -t subscribe -m '["window"]' | while IFS= read -r line; do
        if printf '%s\n' "$line" | is_jquake_event; then
          raise_alert
        fi
      done
    '';
  };
in
{
  home.packages = [
    jquakeAutostart
    jquakeSwayAlert
  ];

  # All graphical sessions (Sway / Plasma).
  systemd.user.services.jquake = {
    Unit = {
      Description = "JQuake earthquake monitor (background)";
      After = [
        "graphical-session.target"
        "xembedsniproxy-jquake.service"
      ];
      Wants = [ "xembedsniproxy-jquake.service" ];
      BindsTo = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${jquakeAutostart}/bin/jquake-autostart";
      Restart = "on-failure";
      RestartSec = 5;
      # AWT / tray need a display; inherit from the graphical session.
      Environment = [
        "_JAVA_AWT_WM_NONREPARENTING=1"
      ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Sway-only: XEmbed → SNI so JQuake's tray icon appears in waybar.
  # Plasma already runs plasma-xembedsniproxy; skip there.
  systemd.user.services.xembedsniproxy-jquake = {
    Unit = {
      Description = "XEmbed→SNI tray proxy for JQuake (Sway)";
      After = [ "graphical-session.target" ];
      BindsTo = [ "graphical-session.target" ];
      ConditionEnvironment = "XDG_CURRENT_DESKTOP=sway";
    };
    Service = {
      Type = "simple";
      ExecStart = xembedsniproxyBin;
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Sway-only: fullscreen + unlock on alert window map/urgent.
  systemd.user.services.jquake-sway-alert = {
    Unit = {
      Description = "Raise JQuake fullscreen over swaylock on alert";
      After = [
        "graphical-session.target"
        "jquake.service"
      ];
      BindsTo = [ "graphical-session.target" ];
      ConditionEnvironment = "XDG_CURRENT_DESKTOP=sway";
    };
    Service = {
      Type = "simple";
      ExecStart = "${jquakeSwayAlert}/bin/jquake-sway-alert";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Compositor-side sticky/fullscreen when the main window maps (alert / tray open).
  wayland.windowManager.sway.extraConfig = lib.mkAfter ''
    # JQuake (XWayland): alert / tray-open → sticky fullscreen.
    for_window ${swayCriteria} fullscreen enable, sticky enable
    # AWT SystemTray embed: hide the black JavaEmbeddedFrame square that
    # xembedsniproxy sometimes leaves visible on Sway/XWayland.
    for_window [title="^JavaEmbeddedFrame$"] floating enable, border none, move to scratchpad
  '';
}
