# Shared Intel laptop firmware + VA-API (8th+ gen iGPU / SOF).
{ pkgs, ... }:

{
  # SOF DSP firmware (Tiger Lake Chromebook + 10th+ gen Intel VAIO).
  # Keep redistributable firmware from modules/nixos/common.nix and add SOF here.
  hardware.firmware = [ pkgs.sof-firmware ];

  # Intel iGPU (8th+ gen / Iris Xe / Core Ultra): VA-API for Parsec's
  # FFMPEG hardware encode/decode. Without intel-media-driver there is no
  # iHD_drv_video.so under /run/opengl-driver and Parsec falls back to software.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver ];
  };

  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
}
