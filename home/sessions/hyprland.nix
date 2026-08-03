# Hyprland greetd sessions: Caelestia-AW and end4-pC (Illogical Impulse).
{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

let
  polkitAgent = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1";
  pactl = "${pkgs.pulseaudio}/bin/pactl";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  konsole = "${pkgs.kdePackages.konsole}/bin/konsole";

  # Shared classic-.conf preamble (Caelestia + end4 fallback).
  # Super+Space stays free for Fcitx5/Mozc; launchers use Super+R.
  sharedPreamble = ''
    monitor=,preferred,auto,1

    env = XDG_CURRENT_DESKTOP,Hyprland
    env = XDG_SESSION_DESKTOP,Hyprland
    env = XDG_SESSION_TYPE,wayland
    env = QT_QPA_PLATFORM,wayland
    env = MOZ_ENABLE_WAYLAND,1

    exec-once = dbus-update-activation-environment --systemd --all
    exec-once = systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE QT_QPA_PLATFORM
    exec-once = ${polkitAgent}
    exec-once = fcitx5 -d --replace
    exec-once = wl-paste --type text --watch cliphist store
    exec-once = wl-paste --type image --watch cliphist store

    input {
      kb_layout = jp
      follow_mouse = 1
      touchpad {
        natural_scroll = false
        tap-to-click = true
      }
    }

    general {
      gaps_in = 4
      gaps_out = 8
      border_size = 2
    }

    decoration {
      rounding = 8
    }

    misc {
      disable_hyprland_logo = true
      force_default_wallpaper = 0
      vfr = true
    }

    # PulseAudio volume (PipeWire audio is off on sof-rt5682).
    bindel = , XF86AudioRaiseVolume, exec, ${pactl} set-sink-volume @DEFAULT_SINK@ +5%
    bindel = , XF86AudioLowerVolume, exec, ${pactl} set-sink-volume @DEFAULT_SINK@ -5%
    bindl = , XF86AudioMute, exec, ${pactl} set-sink-mute @DEFAULT_SINK@ toggle
    bindl = , XF86AudioMicMute, exec, ${pactl} set-source-mute @DEFAULT_SOURCE@ toggle
    bindel = , XF86MonBrightnessUp, exec, ${brightnessctl} set +5%
    bindel = , XF86MonBrightnessDown, exec, ${brightnessctl} set 5%-

    bind = SUPER, Return, exec, ${konsole}
    bind = SUPER, Q, killactive,
    bind = SUPER SHIFT, E, exit,
    bind = SUPER, F, fullscreen,
  '';

  caelestiaConf = ''
    ${sharedPreamble}
    exec-once = caelestia shell -d
    bind = SUPER, R, exec, caelestia shell drawers toggle launcher
  '';

  # Classic .conf fallback when greetd still runs an older wrapper, or lua is missing.
  end4Conf = ''
    ${sharedPreamble}
    env = qsConfig,end4-pC
    env = QUICKSHELL_CONFIG_NAME,end4-pC
    exec-once = qs -c end4-pC
    bind = SUPER, Escape, global, quickshell:settingsToggle
    bind = SUPER, R, global, quickshell:searchToggle
  '';

  # Patch end4-pC so color/wallpaper scripts target this qs config name, not "ii".
  end4PcPatched =
    pkgs.runCommand "end4-pC-patched"
      {
        preferLocalBuild = true;
      }
      ''
        mkdir -p "$out"
        cp -a --no-preserve=mode ${inputs.end4-pc}/. "$out/"
        find "$out" -type f \( -name '*.sh' -o -name '*.qml' -o -name '*.py' \) \
          -exec sed -i \
            -e 's/QUICKSHELL_CONFIG_NAME="ii"/QUICKSHELL_CONFIG_NAME="end4-pC"/g' \
            -e 's/QUICKSHELL_CONFIG_NAME=ii/QUICKSHELL_CONFIG_NAME=end4-pC/g' \
            {} +
      '';

  iiHypr = "${inputs.dots-hyprland}/dots/.config/hypr";

  # Hyprland resolves hyprland.lua through symlinks into the Nix store. Lua
  # `require("custom.*")` then loads siblings of that resolved path — NOT
  # ~/.config/hypr/custom. Bundle lua + hyprland/ + custom/ together and pin
  # qsConfig to end4-pC so stock "ii" does not blank the desktop.
  hyprEnd4Root =
    pkgs.runCommand "hypr-end4-root"
      {
        preferLocalBuild = true;
      }
      ''
        mkdir -p "$out"
        cp -a ${iiHypr}/hyprland.lua "$out/"
        cp -a ${iiHypr}/hyprland "$out/"
        cp -a ${iiHypr}/hypridle.conf "$out/"
        cp -a ${iiHypr}/hyprlock.conf "$out/"
        cp -a ${iiHypr}/hyprlock "$out/"
        cp -a ${iiHypr}/custom "$out/"
        chmod -R u+w "$out"
        cat > "$out/custom/env.lua" <<'EOF'
        -- Loaded before execs; keep qsConfig on end4-pC even if variables load late.
        hl.env("qsConfig", "end4-pC")
        EOF
        cat > "$out/custom/variables.lua" <<'EOF'
        -- Mitac: end4-pC Quickshell instead of stock illogical-impulse "ii".
        hl.env("qsConfig", "end4-pC")
        EOF
        cat > "$out/custom/execs.lua" <<EOF
        hl.on("hyprland.start", function ()
            hl.exec_cmd("${polkitAgent}")
            hl.exec_cmd("fcitx5 -d --replace")
            hl.exec_cmd("wl-paste --type text --watch cliphist store")
            hl.exec_cmd("wl-paste --type image --watch cliphist store")
            hl.exec_cmd("bash -lc 'qs -c end4-pC >>\"\$HOME/.cache/qs-end4.log\" 2>&1'")
        end)
        EOF
      '';
in
{
  imports = [
    inputs.caelestia-shell-aw.homeManagerModules.default
  ];

  # Start from Hyprland exec-once only (not every graphical-session / Plasma).
  programs.caelestia = {
    enable = true;
    systemd.enable = false;
    cli.enable = true;
    settings = {
      paths.wallpaperDir = "~/Pictures/Wallpapers";
    };
  };

  # Caelestia-AW: dedicated classic .conf (greetd wrapper passes --config).
  xdg.configFile."hypr/caelestia.conf".text = caelestiaConf;

  # end4-pC classic fallback (older greetd wrappers / missing lua).
  xdg.configFile."hypr/end4.conf".text = end4Conf;

  # end4-pC: Illogical Impulse Hyprland tree (required by hyprland-startup).
  xdg.configFile."hypr/hyprland.lua".source = "${hyprEnd4Root}/hyprland.lua";
  xdg.configFile."hypr/hyprland".source = "${hyprEnd4Root}/hyprland";
  xdg.configFile."hypr/custom".source = "${hyprEnd4Root}/custom";
  xdg.configFile."hypr/hypridle.conf".source = "${hyprEnd4Root}/hypridle.conf";
  xdg.configFile."hypr/hyprlock.conf".source = "${hyprEnd4Root}/hyprlock.conf";
  xdg.configFile."hypr/hyprlock".source = "${hyprEnd4Root}/hyprlock";

  # end4-pC Quickshell. Also expose as "ii" so a mistaken qsConfig=ii still works.
  xdg.configFile."quickshell/end4-pC".source = end4PcPatched;
  xdg.configFile."quickshell/ii".source = end4PcPatched;

  # Skip end4 FirstRunExperience wallpaper/matugen cascade on a fresh home.
  home.activation.end4SkipFirstRun = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    state="${config.home.homeDirectory}/.local/state/quickshell/user"
    mkdir -p "$state" \
      "${config.home.homeDirectory}/.config/illogical-impulse" \
      "${config.home.homeDirectory}/.local/state/quickshell/user/generated"
    if [ ! -f "$state/first_run.txt" ]; then
      printf '%s\n' 'This file is just here to confirm you have been greeted :>' \
        > "$state/first_run.txt"
    fi
  '';

  home.activation.caelestiaWallpaperDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${config.home.homeDirectory}/Pictures/Wallpapers/Animated"
  '';

  home.packages = with pkgs; [
    # Caelestia-AW video wallpaper thumbnails / decode helpers
    ffmpeg
    python3Packages.pillow
  ];
}
