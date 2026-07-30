{ pkgs, ... }:

{
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "jp";
    variant = "";
  };

  # greetd/tuigreet wraps X11 sessions as `startx /usr/bin/env <Exec>`.
  # Without this, `startx` is missing and Plasma (X11) exits immediately
  # (journal: session type=x11 then closed within ~1s, no Xorg log).
  services.xserver.displayManager.startx.enable = true;

  services.desktopManager.plasma6.enable = true;
  # Session chooser is greetd+tuigreet (see greetd.nix); keep Plasma as a
  # selectable desktop only.
  services.displayManager.plasma-login-manager.enable = false;

  # delbin / sof-rt5682: PipeWire's ALSA backend hits a known Tiger Lake SOF
  # failure mode (spa.alsa Broken pipe → last buffer loops forever on the amp).
  # Keep PipeWire for Plasma Wayland (screencast etc.), but use PulseAudio for
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
      unload-module module-udev-detect
      unload-module module-alsa-card
      unload-module module-null-sink
      load-module module-alsa-sink device=hw:0,0 sink_name=speaker sink_properties=device.description=Speakers tsched=false
      # Headset capture: avoid source_properties (Pulse logs "Invalid properties"
      # with escaped descriptions). .nofail keeps speaker up if mic open fails.
      load-module module-alsa-source device=hw:0,1 source_name=headset_mic tsched=false
      set-default-sink speaker
    '';
  };
  security.rtkit.enable = true;

  # Bluetooth + A2DP audio (PulseAudio). Plasma uses Bluedevil for pairing.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.printing.enable = true;

  # auto-cpufreq manages governors/turbo; conflicts with power-profiles-daemon.
  services.power-profiles-daemon.enable = false;
  services.auto-cpufreq = {
    enable = true;
    settings = {
      charger = {
        governor = "performance";
        turbo = "auto";
      };
      battery = {
        governor = "powersave";
        turbo = "auto";
      };
    };
  };
}
