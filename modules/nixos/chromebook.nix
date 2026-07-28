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
      ExecStart = "${pkgs.alsa-utils}/bin/alsactl init";
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

  # --- Keyboard: ChromeOS-style top row via keyd ---
  # Search key often appears as leftmeta; keep meta and map F-keys to media actions.
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];
        settings = {
          main = {
            f1 = "back";
            f2 = "forward";
            f3 = "refresh";
            f4 = "f11";
            f5 = "f5";
            f6 = "brightnessdown";
            f7 = "brightnessup";
            f8 = "mute";
            f9 = "volumedown";
            f10 = "volumeup";
            # Search (leftmeta) stays meta; hold for overlay if desired:
            # leftmeta = "layer(meta)";
          };
        };
      };
    };
  };

  # Palm rejection + Flip tablet mode with keyd virtual keyboard
  environment.etc."libinput/local-overrides.quirks".text = ''
    [keyd virtual keyboard]
    MatchName=keyd virtual keyboard
    AttrKeyboardIntegration=internal
    ModelTabletModeNoSuspend=1
  '';
}
