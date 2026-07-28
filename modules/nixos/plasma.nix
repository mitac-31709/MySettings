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

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # Slightly larger default quantum reduces SOF DSP underruns that can leave
    # the card in a Broken-pipe / stuck-buffer state on Tiger Lake Chromebooks.
    extraConfig.pipewire."99-sof-clock" = {
      "context.properties" = {
        "default.clock.quantum" = 1024;
        "default.clock.min-quantum" = 256;
        "default.clock.max-quantum" = 2048;
      };
    };
    wireplumber = {
      enable = true;
      # delbin / sof-rt5682: PipeWire idle-suspend + tight ALSA buffering is a
      # common cause of intermittent speaker glitches (same class of bugs as
      # WeirdTreeThing/chromebook-linux-audio#2 — Broken pipe after recover).
      extraConfig."51-sof-chromebook" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {
                "node.name" = "~alsa_output.pci-0000_00_1f.3-platform-tgl_rt5682_def.*";
              }
              {
                "node.name" = "~alsa_input.pci-0000_00_1f.3-platform-tgl_rt5682_def.*";
              }
            ];
            actions = {
              update-props = {
                # Keep the PCM open; SOF often fails to recover after suspend.
                "session.suspend-timeout-seconds" = 0;
                # Extra headroom for DSP batch DMA (avoids XRUN → Broken pipe).
                "api.alsa.headroom" = 1024;
              };
            };
          }
        ];
      };
    };
  };

  # Bluetooth + A2DP audio (PipeWire / WirePlumber). Plasma uses Bluedevil for pairing.
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
