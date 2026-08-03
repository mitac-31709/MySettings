# Sway Home Manager: primary desktop — waybar / mako / swayidle + apps(fzf).
# Visual language stays terminal/greeter-adjacent (dark + cyan).
{
  pkgs,
  lib,
  ...
}:

let
  ghosttyBin = "${pkgs.ghostty}/bin/ghostty";
  swaylockBin = "${pkgs.swaylock}/bin/swaylock";
  swayidleBin = "${pkgs.swayidle}/bin/swayidle";
  waybarBin = "${pkgs.waybar}/bin/waybar";
  polkitAgent = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1";
  pactl = "${pkgs.pulseaudio}/bin/pactl";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  grim = "${pkgs.grim}/bin/grim";
  slurp = "${pkgs.slurp}/bin/slurp";
  wlCopy = "${pkgs.wl-clipboard}/bin/wl-copy";
  # Ghostty + apps(fzf): keyboard list UI closest to tuigreet.
  appsLauncher = "${ghosttyBin} --class=mitac-apps -e apps";
  lockCmd = "${swaylockBin} -f -c 0b0f14";
in
{
  wayland.windowManager.sway = {
    enable = true;
    package = null; # use system programs.sway
    wrapperFeatures.gtk = true;
    checkConfig = false;
    config = {
      modifier = "Mod4";
      terminal = ghosttyBin;
      menu = appsLauncher;

      # Dark solid backdrop + cyan accents (greeter / classic TUI vibe).
      output."*" = {
        bg = "#0b0f14 solid_color";
      };

      fonts = {
        names = [ "JetBrainsMono Nerd Font" ];
        size = 11.0;
      };

      colors = {
        focused = {
          border = "#33c5c5";
          background = "#0b0f14";
          text = "#e6edf3";
          indicator = "#33c5c5";
          childBorder = "#33c5c5";
        };
        focusedInactive = {
          border = "#3a4656";
          background = "#0b0f14";
          text = "#9aa7b5";
          indicator = "#3a4656";
          childBorder = "#3a4656";
        };
        unfocused = {
          border = "#1c2430";
          background = "#0b0f14";
          text = "#6b7785";
          indicator = "#1c2430";
          childBorder = "#1c2430";
        };
        urgent = {
          border = "#e06c75";
          background = "#0b0f14";
          text = "#e6edf3";
          indicator = "#e06c75";
          childBorder = "#e06c75";
        };
      };

      gaps = {
        inner = 4;
        outer = 4;
      };

      window = {
        border = 2;
        titlebar = false;
      };

      # Status bar is waybar (started in startup).
      bars = [ ];

      input."type:touchpad" = {
        natural_scroll = "disabled";
        tap = "enabled";
        dwt = "disabled";
      };

      keybindings =
        let
          mod = "Mod4";
        in
        lib.mkOptionDefault {
          # Super+F → apps; restore default Super+R (resize) by not overriding it.
          # Fullscreen moves to Super+Shift+F.
          "${mod}+f" = "exec ${appsLauncher}";
          "${mod}+Shift+f" = "fullscreen";
          "Ctrl+Alt+t" = "exec ${ghosttyBin}";
          "${mod}+Return" = "exec ${ghosttyBin}";
          "${mod}+l" = "exec ${lockCmd}";
          # Volume / mic (PulseAudio on sof-rt5682 Chromebook).
          "XF86AudioRaiseVolume" = "exec ${pactl} set-sink-volume @DEFAULT_SINK@ +5%";
          "XF86AudioLowerVolume" = "exec ${pactl} set-sink-volume @DEFAULT_SINK@ -5%";
          "XF86AudioMute" = "exec ${pactl} set-sink-mute @DEFAULT_SINK@ toggle";
          "XF86AudioMicMute" = "exec ${pactl} set-source-mute @DEFAULT_SOURCE@ toggle";
          "XF86MonBrightnessUp" = "exec ${brightnessctl} set +5%";
          "XF86MonBrightnessDown" = "exec ${brightnessctl} set 5%-";
          # Screenshots.
          "Print" = "exec ${grim} - | ${wlCopy}";
          "${mod}+Shift+s" = "exec ${grim} -g \"$(${slurp})\" - | ${wlCopy}";
        };

      startup = [
        { command = polkitAgent; }
        { command = "fcitx5 -d --replace"; }
        { command = "wl-paste --type text --watch cliphist store"; }
        { command = "wl-paste --type image --watch cliphist store"; }
        { command = waybarBin; }
        {
          command = ''
            ${swayidleBin} -w \
              timeout 600 '${lockCmd}' \
              timeout 900 'swaymsg "output * power off"' \
              resume 'swaymsg "output * power on"' \
              before-sleep '${lockCmd}'
          '';
        }
      ];
    };

    extraConfig = ''
      for_window [app_id="mitac-apps"] floating enable, sticky enable, border pixel 2
      for_window [class="mitac-apps"] floating enable, sticky enable, border pixel 2
    '';
  };

  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "bottom";
        height = 28;
        modules-left = [
          "sway/workspaces"
          "sway/mode"
        ];
        modules-center = [ "sway/window" ];
        modules-right = [
          "cpu"
          "memory"
          "battery"
          "network"
          "pulseaudio"
          "clock"
          "tray"
        ];
        "sway/workspaces" = {
          disable-scroll = true;
          all-outputs = true;
        };
        "sway/window" = {
          max-length = 48;
        };
        cpu = {
          format = "cpu {usage}%";
          interval = 5;
        };
        memory = {
          format = "mem {percentage}%";
          interval = 5;
        };
        battery = {
          format = "{capacity}% {icon}";
          format-icons = [
            "batt"
            "batt"
            "batt"
            "batt"
            "batt"
          ];
          format-charging = "{capacity}% chg";
          states = {
            warning = 30;
            critical = 15;
          };
        };
        network = {
          format-wifi = "{essid}";
          format-ethernet = "eth";
          format-disconnected = "offline";
          tooltip-format = "{ifname}: {ipaddr}";
        };
        pulseaudio = {
          format = "vol {volume}%";
          format-muted = "mute";
          on-click = "${pactl} set-sink-mute @DEFAULT_SINK@ toggle";
        };
        clock = {
          format = "{:%a %m-%d %H:%M}";
          tooltip-format = "{:%Y-%m-%d %H:%M:%S}";
        };
      };
    };
    style = ''
      * {
        border: none;
        border-radius: 0;
        font-family: "JetBrainsMono Nerd Font";
        font-size: 11px;
        min-height: 0;
      }
      window#waybar {
        background: #0b0f14;
        color: #9fe7e7;
      }
      #workspaces button {
        padding: 0 6px;
        color: #6b7785;
        background: transparent;
      }
      #workspaces button.focused {
        color: #e6edf3;
        background: #15383a;
        border-bottom: 2px solid #33c5c5;
      }
      #workspaces button.urgent {
        color: #e6edf3;
        background: #3a1a1e;
      }
      #mode {
        color: #e06c75;
        padding: 0 8px;
      }
      #window {
        color: #9aa7b5;
        padding: 0 8px;
      }
      #cpu, #memory, #battery, #network, #pulseaudio, #clock, #tray {
        padding: 0 8px;
        color: #9fe7e7;
      }
      #battery.warning { color: #e5c07b; }
      #battery.critical { color: #e06c75; }
      #network.disconnected { color: #6b7785; }
      #pulseaudio.muted { color: #6b7785; }
    '';
  };

  services.mako = {
    enable = true;
    settings = {
      font = "JetBrainsMono Nerd Font 11";
      background-color = "#0b0f14dd";
      text-color = "#e6edf3";
      border-color = "#33c5c5";
      border-size = 2;
      border-radius = 0;
      padding = 10;
      margin = 8;
      default-timeout = 8000;
      max-visible = 4;
      layer = "overlay";
    };
  };
}
