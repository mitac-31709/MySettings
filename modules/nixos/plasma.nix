{ pkgs, ... }:

{
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "jp";
    variant = "";
  };

  services.desktopManager.plasma6.enable = true;
  services.displayManager.plasma-login-manager.enable = true;

  # NumLock on at the Plasma Login Manager greeter (0 = on).
  # See ArchWiki: /var/lib/plasmalogin/.config/kdedefaults/kcminputrc
  systemd.tmpfiles.settings."plasmalogin-numlock" = {
    "/var/lib/plasmalogin/.config".d = {
      user = "plasmalogin";
      group = "plasmalogin";
      mode = "0755";
    };
    "/var/lib/plasmalogin/.config/kdedefaults".d = {
      user = "plasmalogin";
      group = "plasmalogin";
      mode = "0755";
    };
    "/var/lib/plasmalogin/.config/kdedefaults/kcminputrc"."C+" = {
      user = "plasmalogin";
      group = "plasmalogin";
      mode = "0644";
      argument = "${pkgs.writeText "plasmalogin-kcminputrc" ''
        [Keyboard]
        NumLock=0
      ''}";
    };
  };

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
