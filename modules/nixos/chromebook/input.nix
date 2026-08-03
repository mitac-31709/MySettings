# Chromebook keyboard (keyd) + libinput quirks for keyd virtual keyboard.
{ ... }:

{
  # --- Keyboard: WeirdTreeThing cros-keyboard-map (keyd) ---
  # Chromebook top-row scancodes are Vivaldi keys (back/refresh/zoom/...), not
  # F1–F10. Remapping only `fN` never reaches tuigreet. Use the layout from
  # https://github.com/WeirdTreeThing/cros-keyboard-map for this board's
  # function_row_physmap (delbin: EA E7 91 92 93 94 95 A0 AE B0):
  #   bare top row → ChromeOS actions; Search+top row → F1–F10.
  # tuigreet sessions (F3): hold Search + 3rd key (zoom / 全画面).
  services.keyd = {
    enable = true;
    keyboards = {
      # Match cros_ec / AT / Hammer IDs from cros-keyboard-map (not all USB boards).
      cros = {
        ids = [
          # AT Translated Set 2 (i8042 Chromebook keyboard). Do not include
          # k:0000:0000 — that also matches sof-rt5682 Headset Jack.
          "k:0001:0001"
          "k:18d1:502b"
          "k:18d1:5030"
          "k:18d1:503c"
          "k:18d1:503d"
          "k:18d1:5044"
          "k:18d1:504c"
          "k:18d1:5050"
          "k:18d1:5052"
          "k:18d1:5057"
          "k:18d1:505b"
          "k:18d1:5061"
        ];
        extraConfig = ''
          [main]
          f1 = back
          f2 = refresh
          f3 = f11
          f4 = scale
          f5 = sysrq
          f6 = brightnessdown
          f7 = brightnessup
          f8 = mute
          f9 = volumedown
          f10 = volumeup

          back = back
          refresh = refresh
          zoom = f11
          scale = scale
          sysrq = sysrq
          brightnessdown = brightnessdown
          brightnessup = brightnessup
          mute = mute
          volumedown = volumedown
          volumeup = volumeup

          f13 = coffee
          sleep = coffee

          [meta]
          f1 = f1
          f2 = f2
          f3 = f3
          f4 = f4
          f5 = f5
          f6 = f6
          f7 = f7
          f8 = f8
          f9 = f9
          f10 = f10

          back = f1
          refresh = f2
          zoom = f3
          scale = f4
          sysrq = f5
          brightnessdown = f6
          brightnessup = f7
          mute = f8
          volumedown = f9
          volumeup = f10

          [alt]
          backspace = delete
          brightnessdown = kbdillumdown
          brightnessup = kbdillumup
          f6 = kbdillumdown
          f7 = kbdillumup

          [control]
          f5 = sysrq
          scale = sysrq

          [altgr]
          backspace = delete
          left = home
          right = end
          up = pageup
          down = pagedown

          [control+alt]
          backspace = C-A-delete
          f1 = C-A-f1
          f2 = C-A-f2
          f3 = C-A-f3
          f4 = C-A-f4
          f5 = C-A-f5
          f6 = C-A-f6
          f7 = C-A-f7
          f8 = C-A-f8
          f9 = C-A-f9
          f10 = C-A-f10
          back = C-A-f1
          refresh = C-A-f2
          zoom = C-A-f3
          scale = C-A-f4
          sysrq = C-A-f5
          brightnessdown = C-A-f6
          brightnessup = C-A-f7
          mute = C-A-f8
          volumedown = C-A-f9
          volumeup = C-A-f10
        '';
      };
    };
  };

  # Palm rejection + Flip tablet mode with keyd virtual keyboard
  # (same content as cros-keyboard-map local-overrides.quirks)
  environment.etc."libinput/local-overrides.quirks".text = ''
    [keyd virtual keyboard]
    MatchName=keyd virtual keyboard
    AttrKeyboardIntegration=internal
    ModelTabletModeNoSuspend=1
  '';
}
