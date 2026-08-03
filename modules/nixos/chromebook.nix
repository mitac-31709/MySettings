# ASUS CX5500FE / delbin / volteer / DELBIN_XHVI
#
# Chromebook-specific settings split by concern under ./chromebook/.
{ ... }:

{
  imports = [
    ./chromebook/audio.nix
    ./chromebook/power.nix
    ./chromebook/graphics.nix
    ./chromebook/input.nix
  ];
}
