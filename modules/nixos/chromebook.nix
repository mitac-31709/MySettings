# ASUS CX5500FE / delbin / volteer / DELBIN_XHVI
#
# Chromebook-specific settings: keyd top-row, SOF audio UCM, Flip tablet quirks.
{
  pkgs,
  inputs,
  ...
}:

let
  # Merge upstream UCM with ChromeOS overlays (WeirdTreeThing) without replacing
  # alsa-ucm-conf globally (avoids large rebuilds).
  alsa-ucm-conf-chromebook = pkgs.runCommand "alsa-ucm-conf-chromebook" { } ''
    mkdir -p $out/share/alsa/ucm2
    cp -a --no-preserve=mode ${pkgs.alsa-ucm-conf}/share/alsa/ucm2/. $out/share/alsa/ucm2/
    cp -a --no-preserve=mode ${inputs.alsa-ucm-conf-cros}/ucm2/. $out/share/alsa/ucm2/
    if [ -d ${inputs.alsa-ucm-conf-cros}/overrides ]; then
      cp -a --no-preserve=mode ${inputs.alsa-ucm-conf-cros}/overrides/. $out/share/alsa/ucm2/
    fi
  '';
in
{
  # --- Firmware / power (volteer uses SOF) ---
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.sof-firmware ];

  # Intel Tiger Lake iGPU (i3-1115G4 / device 0x9a78): VA-API for Parsec's
  # FFMPEG hardware encode/decode. Without intel-media-driver there is no
  # iHD_drv_video.so under /run/opengl-driver and Parsec falls back to software.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver ];
  };

  # Session + system env so PipeWire/WirePlumber and early tools both see UCM.
  environment.sessionVariables = {
    ALSA_CONFIG_UCM2 = "${alsa-ucm-conf-chromebook}/share/alsa/ucm2";
    LIBVA_DRIVER_NAME = "iHD";
  };
  environment.variables.ALSA_CONFIG_UCM2 = "${alsa-ucm-conf-chromebook}/share/alsa/ucm2";

  # Apply UCM BootSequence (rt5682 / max98373 mixer state) once the card exists.
  # Without this, speakers can come up muted or on the wrong route until something
  # else opens the UCM profile. Also raise max98373 digital/speaker levels — with
  # PulseAudio we open hw:0,0 directly (no UCM Speaker enable path).
  systemd.services.chromebook-alsactl-init = {
    description = "Initialize Chromebook ALSA card state";
    after = [ "sound.target" ];
    wantedBy = [ "sound.target" ];
    serviceConfig = {
      Type = "oneshot";
      # alsactl init exits 99 when UCM import fails but still applies a generic
      # init ("Hardware is initialized using a generic method") — treat as OK.
      ExecStart = "${pkgs.alsa-utils}/bin/alsactl init";
      SuccessExitStatus = [
        0
        99
      ];
      ExecStartPost = pkgs.writeShellScript "chromebook-speaker-levels" ''
        set +e
        amixer=${pkgs.alsa-utils}/bin/amixer
        $amixer -c 0 sset 'Left Digital' 80%
        $amixer -c 0 sset 'Right Digital' 80%
        $amixer -c 0 sset 'Left Spk' on
        $amixer -c 0 sset 'Right Spk' on
        $amixer -c 0 sset 'Left Speaker' 8
        $amixer -c 0 sset 'Right Speaker' 8
        true
      '';
      RemainAfterExit = true;
    };
  };

  # SOF + max98373 often need a fresh codec init after S3.
  powerManagement.resumeCommands = ''
    ${pkgs.alsa-utils}/bin/alsactl init || true
    ${pkgs.alsa-utils}/bin/amixer -c 0 sset 'Left Digital' 80% || true
    ${pkgs.alsa-utils}/bin/amixer -c 0 sset 'Right Digital' 80% || true
    ${pkgs.alsa-utils}/bin/amixer -c 0 sset 'Left Spk' on || true
    ${pkgs.alsa-utils}/bin/amixer -c 0 sset 'Right Spk' on || true
    ${pkgs.alsa-utils}/bin/amixer -c 0 sset 'Left Speaker' 8 || true
    ${pkgs.alsa-utils}/bin/amixer -c 0 sset 'Right Speaker' 8 || true
  '';

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
