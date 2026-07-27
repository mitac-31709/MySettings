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
    wireplumber.enable = true;
  };

  # Bluetooth + A2DP audio (PipeWire / WirePlumber). Plasma uses Bluedevil for pairing.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.printing.enable = true;

  services.power-profiles-daemon.enable = true;
}
