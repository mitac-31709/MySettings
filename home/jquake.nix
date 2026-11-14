# JQuake: login autostart, tray background, alert fullscreen over swaylock.
#
# - Patches a few Settings.properties keys on each start (tray / always-on-top /
#   wake screen / no window until alert) without rewriting the whole file.
# - Sway: AWT SystemTray needs an XEmbed tray host. We use offscreen stalonetray
#   (not xembedsniproxy→waybar) so the broken JavaEmbeddedFrame SNI icon never
#   appears in the bar; alerts still raise the main window.
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

  stalonetrayBin = "${pkgs.stalonetray}/bin/stalonetray";

  # for_window alone races map; re-apply after the tray window exists.
  hideStalonetray = pkgs.writeShellScript "stalonetray-jquake-hide" ''
    set -euo pipefail
    for _ in $(seq 1 40); do
      if ${pkgs.sway}/bin/swaymsg -t get_tree \
        | ${pkgs.jq}/bin/jq -e '
            [.. | objects | select(.window_properties.class? == "stalonetray")] | length > 0
          ' >/dev/null; then
        ${pkgs.sway}/bin/swaymsg \
          '[class="^stalonetray$"] floating enable, border none, sticky enable, opacity 0, move absolute position -2000 px -2000 px' \
          >/dev/null
        exit 0
      fi
      sleep 0.25
    done
    exit 0
  '';

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

      # Defaults for user preferences (only set when missing so GUI tweaks stick).
      set_default_prop() {
        local key="$1" val="$2"
        if [[ ! -f "$props" ]] || ! grep -q "^''${key}=" "$props"; then
          printf '%s=%s\n' "$key" "$val" >>"$props"
        fi
      }

      # Location / initial map view (Tokyo) & UI layout.
      set_default_prop firstOpen false
      set_default_prop userLatitude 35.68952
      set_default_prop userLongitude 139.74409
      set_default_prop userVisible true
      set_default_prop includeUserInZoom false
      set_default_prop homeViewNW "45.62207;126.89925"
      set_default_prop homeViewSE "29.92448;146.10139"
      set_default_prop fixedMode false
      set_default_prop resetViewAfterEvent true
      set_default_prop displayPrefList true
      set_default_prop displayCityNames true
      set_default_prop displayEQScrollBar true
      set_default_prop displayMiniMap true
      set_default_prop roundRectangles true
      set_default_prop intensityIcon true
      set_default_prop useSmallIcons false
      set_default_prop useShindoColor true
      set_default_prop showClosestSation true
      set_default_prop langChoice 0
      set_default_prop serverChoice 0
      set_default_prop displayChoice 2
      set_default_prop displayChoiceSub 3
      set_default_prop interfaceDisplayChoice 0
      set_default_prop interfaceDisplayChoiceSub 0
      set_default_prop interfaceScale 1.00000
      set_default_prop mapScale 1.00000
      set_default_prop useSystemProxy true

      # Dark theme colors.
      set_default_prop bg "51;52;57"
      set_default_prop mapBg "31;32;37"
      set_default_prop polyColor "63;64;69"
      set_default_prop fontColor "255;255;255"

      # Audio.
      set_default_prop mute false
      set_default_prop volume -15.00000
      set_default_prop soundPeripheral 0
      set_default_prop eqSpeakerChoice 0
      set_default_prop soundEEW1 true
      set_default_prop soundEEW2 true
      set_default_prop soundEQInfo true
      set_default_prop soundTsunami true
      set_default_prop teleseismicSound true
      set_default_prop soundShindo0 true
      set_default_prop soundShindo1 true
      set_default_prop soundShindo2 true
      set_default_prop soundPGA1 true
      set_default_prop soundPGA2 true

      # Alerts, tsunami, local thresholds & radii.
      set_default_prop advancedEEW false
      set_default_prop forceForecastOnDeep false
      set_default_prop EQInfoIntensity 5
      set_default_prop EEW1ShindoMin 0
      set_default_prop EEW1ShindoMinLoc 1
      set_default_prop EEW2ShindoMinLoc 0
      set_default_prop EEW2ShindoMinNat 0
      set_default_prop tsunamiChoice 0
      set_default_prop showTsunami true
      set_default_prop tsunamiBrowser true
      set_default_prop popEEW1 true
      set_default_prop popEEW2 true
      set_default_prop popShindo0 true
      set_default_prop popShindo1 true
      set_default_prop popShindo2 true
      set_default_prop popPGA1 true
      set_default_prop popPGA2 true
      set_default_prop localEEW1 true
      set_default_prop localEEW2 false
      set_default_prop localShindo0 true
      set_default_prop localShindo1 true
      set_default_prop localShindo2 false
      set_default_prop localPGA1 true
      set_default_prop localPGA2 false
      set_default_prop localShindo0Radius 45.00000
      set_default_prop localShindo1Radius 60.00000
      set_default_prop localShindo2Radius 115.00000
      set_default_prop localPGA1Radius 75.00000
      set_default_prop localPGA2Radius 120.00000
      set_default_prop level0ShindoIndex 4
      set_default_prop level1ShindoIndex 2
      set_default_prop level2ShindoIndex 2
      set_default_prop level1PGAIndex 2
      set_default_prop level2PGAIndex 5
      set_default_prop zoomEEW1 6
      set_default_prop zoomEEW2 6
      set_default_prop zoomShindo0 6
      set_default_prop zoomShindo1 6
      set_default_prop zoomShindo2 6
      set_default_prop zoomPGA1 6
      set_default_prop zoomPGA2 6

      # Tray/window: icon + minimize-on-close (stay resident in background).
      set_prop winChoice 2
      # Alerts: raise above other windows; wake DPMS; do not suppress pops.
      set_prop alwaysOnTop true
      set_prop wakeUpScreen true
      set_prop gameMode false
      set_prop persistentMode true
      # Start in tray; popEEW / popShindo / … open the window on events.
      set_prop openOnStartup false

      # Sway: wait for stalonetray so AWT SystemTray.isSupported() is true.
      if [[ "''${XDG_CURRENT_DESKTOP:-}" == "sway" ]]; then
        for _ in $(seq 1 40); do
          if pgrep -x stalonetray >/dev/null 2>&1; then
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

  # Graphical session autostart.
  systemd.user.services.jquake = {
    Unit = {
      Description = "JQuake earthquake monitor (background)";
      After = [
        "graphical-session.target"
        "stalonetray-jquake.service"
      ];
      Wants = [ "stalonetray-jquake.service" ];
      BindsTo = [ "graphical-session.target" ];
      # Logout: AWT dies with Broken pipe then Restart would storm until stop.
      StartLimitIntervalSec = 30;
      StartLimitBurst = 3;
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

  # Offscreen XEmbed tray host so JQuake can background without a waybar SNI
  # (xembedsniproxy published a black JavaEmbeddedFrame icon).
  systemd.user.services.stalonetray-jquake = {
    Unit = {
      Description = "Offscreen XEmbed tray for JQuake (Sway)";
      After = [ "graphical-session.target" ];
      BindsTo = [ "graphical-session.target" ];
      ConditionEnvironment = "XDG_CURRENT_DESKTOP=sway";
      StartLimitIntervalSec = 30;
      StartLimitBurst = 3;
    };
    Service = {
      Type = "simple";
      # Placeholder geometry; sway moves it off-screen + opacity 0 (not
      # scratchpad: Super+- would reveal scratchpad contents).
      # BadWindow on icon destroy is noisy but harmless; keep going.
      ExecStart = "${stalonetrayBin} --geometry 1x1+0+0 --icon-size 16 --window-type utility --window-strut none --kludges force_icons_size";
      ExecStartPost = "${hideStalonetray}";
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
      StartLimitIntervalSec = 30;
      StartLimitBurst = 3;
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
    # Hide stalonetray host off-screen (scratchpad is wrong: Super+- reveals it).
    for_window [class="^stalonetray$"] floating enable, border none, sticky enable, opacity 0, move absolute position -2000 px -2000 px
    for_window [title="^JavaEmbeddedFrame$"] floating enable, border none, sticky enable, opacity 0, move absolute position -2000 px -2000 px
  '';
}
