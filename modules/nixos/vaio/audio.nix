# VAIO laptop audio: PipeWire + WirePlumber + ALSA/PulseAudio/JACK compat + Bluetooth.
{ ... }:

{
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;
  };

  # Bluetooth + A2DP/HFP audio (WirePlumber / PipeWire).
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
}
