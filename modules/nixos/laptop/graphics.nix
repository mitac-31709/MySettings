# Shared Intel laptop firmware + VA-API (8th+ gen iGPU / SOF).
{ pkgs, ... }:

{
  # SOF DSP firmware (Tiger Lake Chromebook + 10th+ gen Intel VAIO).
  # Keep redistributable firmware from modules/nixos/common.nix and add SOF here.
  hardware.firmware = [ pkgs.sof-firmware ];

  # Ice Lake eDP (VAIO): PSR2 left i915_flip stuck in
  # drm_atomic_helper_wait_for_flip_done for minutes, which shows up as a
  # permanent procs_blocked/iowait tax (~1 CPU ≈ 12%). Disable PSR at boot.
  boot.kernelParams = [ "i915.enable_psr=0" ];

  # Intel iGPU (8th+ gen / Iris Xe / Core Ultra): VA-API for Parsec's
  # FFMPEG hardware encode/decode. Without intel-media-driver there is no
  # iHD_drv_video.so under /run/opengl-driver and Parsec falls back to software.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver ];
  };

  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
}
