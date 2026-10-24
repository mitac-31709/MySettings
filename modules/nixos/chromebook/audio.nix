# Chromebook SOF / PulseAudio stack (shared by all greetd sessions).
{
  pkgs,
  inputs,
  lib,
  ...
}:

let
  # Merge upstream UCM with ChromeOS overlays (WeirdTreeThing) without replacing
  # alsa-ucm-conf globally (avoids large rebuilds).
  # Card id is "sofrt5682" (no hyphen) while upstream conf.d uses "sof-rt5682".
  alsa-ucm-conf-chromebook = pkgs.runCommand "alsa-ucm-conf-chromebook" { } ''
    mkdir -p $out/share/alsa/ucm2
    cp -a --no-preserve=mode ${pkgs.alsa-ucm-conf}/share/alsa/ucm2/. $out/share/alsa/ucm2/
    cp -a --no-preserve=mode ${inputs.alsa-ucm-conf-cros}/ucm2/. $out/share/alsa/ucm2/
    if [ -d ${inputs.alsa-ucm-conf-cros}/overrides ]; then
      cp -a --no-preserve=mode ${inputs.alsa-ucm-conf-cros}/overrides/. $out/share/alsa/ucm2/
    fi
    # Kernel card id omits the hyphen; alias so alsactl/alsaucm resolve without
    # falling back to a generic (non-UCM) init.
    if [ -d $out/share/alsa/ucm2/conf.d/sof-rt5682 ] && [ ! -e $out/share/alsa/ucm2/conf.d/sofrt5682 ]; then
      ln -s sof-rt5682 $out/share/alsa/ucm2/conf.d/sofrt5682
      ln -s sof-rt5682.conf $out/share/alsa/ucm2/conf.d/sofrt5682/sofrt5682.conf
    fi
  '';

  ucm2 = "${alsa-ucm-conf-chromebook}/share/alsa/ucm2";

  chromebook-speaker-levels = pkgs.writeShellApplication {
    name = "chromebook-speaker-levels";
    runtimeInputs = [ pkgs.alsa-utils ];
    text = builtins.readFile ./speaker-levels.sh;
  };

  # Stock default.pa loads module-udev-detect before our extraConfig can unload
  # it, which logs a hard "Failed to find a working profile" on sof-rt5682 even
  # though we then bind hw:0,0 / hw:0,1 successfully. Disable udev detect here.
  pulseDefaultPa =
    pkgs.runCommand "chromebook-pulse-default.pa"
      {
        preferLocalBuild = true;
      }
      ''
        sed -E \
          -e 's/^load-module module-udev-detect/# load-module module-udev-detect (chromebook: use explicit alsa sink\/source)/' \
          -e 's/^load-module module-detect/# load-module module-detect/' \
          ${pkgs.pulseaudioFull}/etc/pulse/default.pa >"$out"
      '';
in
{
  # delbin / sof-rt5682: PipeWire's ALSA backend hits a known Tiger Lake SOF
  # failure mode (spa.alsa Broken pipe → last buffer loops forever on the amp).
  # Keep PipeWire for Wayland portals (screencast etc.), but use PulseAudio for
  # actual sound — the workaround documented for this class of Chromebooks.
  services.pipewire = {
    enable = true;
    audio.enable = false;
    alsa.enable = false;
    pulse.enable = false;
    wireplumber.enable = true;
  };
  services.pulseaudio = {
    enable = true;
    support32Bit = true;
    # A2DP / HSP need the full build (codec modules).
    package = pkgs.pulseaudioFull;
    configFile = pulseDefaultPa;
    # Chromebook / this host: libpulse SHM (shared memfd) negotiates then the
    # server drops the client ("接続失敗: 接続切断"). pactl and waybar's
    # pulseaudio module then reconnect in a tight loop; waybar leaks ~50–70
    # MiB/s and OOMs the 8 GiB machine within minutes. Private memory pools
    # work. Keep this until SHM is diagnosed further.
    extraClientConf = ''
      enable-shm = no
    '';
    # Slightly larger fragments reduce SOF underruns vs PipeWire's aggressive
    # scheduling on this DSP.
    daemon.config = {
      default-fragments = 8;
      default-fragment-size-msec = 25;
    };
    # sof-rt5682: module-alsa-card + use_ucm=yes fails ("no working profile")
    # because UCM Mic/DMIC probes error out, leaving only the null sink.
    # Bind speaker PCM (hw:0,0) and headset mic (hw:0,1) directly instead.
    extraConfig = ''
      .nofail
      unload-module module-null-sink
      load-module module-alsa-sink device=hw:0,0 sink_name=speaker sink_properties=device.description=Speakers tsched=false
      # Headset capture: avoid source_properties (Pulse logs "Invalid properties"
      # with escaped descriptions). .nofail keeps speaker up if mic open fails.
      load-module module-alsa-source device=hw:0,1 source_name=headset_mic tsched=false
      set-default-sink speaker
    '';
  };
  security.rtkit.enable = true;

  # Silence dbus-broker "Invalid user-name … user=pulse" from pulseaudio's
  # system.d fragment (we run per-user PA; the policy user still must exist).
  users.groups.pulse = { };
  users.users.pulse = {
    isSystemUser = true;
    group = "pulse";
    home = "/var/lib/pulse";
    createHome = true;
    description = "PulseAudio system user (dbus policy only)";
  };

  # Bluetooth + A2DP audio (PulseAudio). Pair with bluetoothctl.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Session + system env so PulseAudio and early tools both see UCM.
  environment.sessionVariables.ALSA_CONFIG_UCM2 = ucm2;
  environment.variables.ALSA_CONFIG_UCM2 = ucm2;

  environment.systemPackages = [ chromebook-speaker-levels ];

  # Apply UCM BootSequence (rt5682 / max98373 mixer state) once the card exists.
  # Without this, speakers can come up muted or on the wrong route until something
  # else opens the UCM profile. Also raise max98373 digital/speaker levels — with
  # PulseAudio we open hw:0,0 directly (no UCM Speaker enable path).
  systemd.services.chromebook-alsactl-init = {
    description = "Initialize Chromebook ALSA card state";
    after = [ "sound.target" ];
    wantedBy = [ "sound.target" ];
    # System units do not inherit environment.variables; without this, alsactl
    # uses stock ucm2 and fails with "import hw:0 … -2" on every boot.
    environment.ALSA_CONFIG_UCM2 = ucm2;
    serviceConfig = {
      Type = "oneshot";
      # alsactl init exits 99 when UCM import fails but still applies a generic
      # init ("Hardware is initialized using a generic method") — treat as OK.
      ExecStart = "${pkgs.alsa-utils}/bin/alsactl init";
      SuccessExitStatus = [
        0
        99
      ];
      ExecStartPost = "${chromebook-speaker-levels}/bin/chromebook-speaker-levels apply";
      RemainAfterExit = true;
    };
  };

  # SOF + max98373 often need a fresh codec init after S3.
  # sleep-actions runs this outside the user session — set UCM path explicitly.
  powerManagement.resumeCommands = ''
    export ALSA_CONFIG_UCM2=${lib.escapeShellArg ucm2}
    ${pkgs.alsa-utils}/bin/alsactl init || true
    ${chromebook-speaker-levels}/bin/chromebook-speaker-levels apply || true
  '';
}
