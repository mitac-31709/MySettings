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
    cp -a ${pkgs.alsa-ucm-conf}/share/alsa/ucm2/. $out/share/alsa/ucm2/
    cp -a ${inputs.alsa-ucm-conf-cros}/ucm2/. $out/share/alsa/ucm2/
    if [ -d ${inputs.alsa-ucm-conf-cros}/overrides ]; then
      cp -a ${inputs.alsa-ucm-conf-cros}/overrides/. $out/share/alsa/ucm2/
    fi
  '';
in
{
  # --- Firmware / power (volteer uses SOF) ---
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.sof-firmware ];

  environment.sessionVariables.ALSA_CONFIG_UCM2 =
    "${alsa-ucm-conf-chromebook}/share/alsa/ucm2";

  # Optional SOF / codec tweaks for volteer-class boards.
  # Uncomment or extend if speakers/headphones need extra options after checking
  # Chrultrabook setup-audio for tgl/volteer.
  # boot.extraModprobeConfig = ''
  #   options snd-sof-pci fw_path="intel/sof"
  # '';

  # If the card is silent until alsactl init, enable the service below:
  # systemd.services.chromebook-alsactl-init = {
  #   description = "Initialize Chromebook ALSA card state";
  #   after = [ "sound.target" ];
  #   wantedBy = [ "sound.target" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.alsa-utils}/bin/alsactl init";
  #     RemainAfterExit = true;
  #   };
  # };

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
