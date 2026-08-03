# Sway Home Manager: TUI-like chrome + Plasma-parity shortcuts.
# Visual language stays terminal/greeter-adjacent (not a themed DE shell).
{
  pkgs,
  lib,
  ...
}:

let
  konsole = "${pkgs.kdePackages.konsole}/bin/konsole";
  foot = "${pkgs.foot}/bin/foot";
  swaylock = "${pkgs.swaylock}/bin/swaylock";
  polkitAgent = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1";
  # foot + apps(fzf): keyboard list UI closest to tuigreet.
  appsLauncher = "${foot} --app-id=mitac-apps -e apps";
in
{
  wayland.windowManager.sway = {
    enable = true;
    package = null; # use system programs.sway
    wrapperFeatures.gtk = true;
    checkConfig = false;
    config = {
      modifier = "Mod4";
      terminal = konsole;
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

      bars = [
        {
          position = "bottom";
          statusCommand = "${pkgs.i3status}/bin/i3status";
          fonts = {
            names = [ "JetBrainsMono Nerd Font" ];
            size = 10.0;
          };
          colors = {
            background = "#0b0f14";
            statusline = "#9fe7e7";
            separator = "#3a4656";
            focusedWorkspace = {
              border = "#33c5c5";
              background = "#15383a";
              text = "#e6edf3";
            };
            activeWorkspace = {
              border = "#3a4656";
              background = "#1c2430";
              text = "#e6edf3";
            };
            inactiveWorkspace = {
              border = "#0b0f14";
              background = "#0b0f14";
              text = "#6b7785";
            };
            urgentWorkspace = {
              border = "#e06c75";
              background = "#3a1a1e";
              text = "#e6edf3";
            };
          };
        }
      ];

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
          # Plasma-parity + tuigreet-like app pick (fzf via apps).
          "${mod}+r" = "exec ${appsLauncher}";
          "Ctrl+Alt+t" = "exec ${konsole}";
          "${mod}+Return" = "exec ${konsole}";
          "${mod}+l" = "exec ${swaylock} -f -c 0b0f14";
          "${mod}+d" = "exec ${appsLauncher}";
        };

      startup = [
        { command = polkitAgent; }
        { command = "fcitx5 -d --replace"; }
      ];
    };

    extraConfig = ''
      for_window [app_id="mitac-apps"] floating enable, sticky enable, border pixel 2
    '';
  };

  home.packages = with pkgs; [
    foot
    i3status
  ];
}
