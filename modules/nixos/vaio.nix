# VAIO laptop (Intel 8th+ gen iGPU) overrides beyond ./laptop.nix.
{ ... }:

{
  imports = [
    ./vaio/audio.nix
  ];
}
