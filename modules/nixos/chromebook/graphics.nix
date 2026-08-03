# Chromebook firmware + Intel Tiger Lake VA-API (Parsec etc.).
{ pkgs, ... }:

{
  # volteer / delbin uses SOF for audio; keep redistributable firmware from
  # modules/nixos/common.nix and add SOF + iHD here.
  hardware.firmware = [ pkgs.sof-firmware ];

  # Intel Tiger Lake iGPU (i3-1115G4 / device 0x9a78): VA-API for Parsec's
  # FFMPEG hardware encode/decode. Without intel-media-driver there is no
  # iHD_drv_video.so under /run/opengl-driver and Parsec falls back to software.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver ];
  };

  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
}
