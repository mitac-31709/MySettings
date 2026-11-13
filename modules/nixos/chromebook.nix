# ASUS CX5500FE / delbin / volteer / DELBIN_XHVI
#
# Chromebook-specific overrides beyond ./laptop.nix, split by concern under ./chromebook/.
{ ... }:

{
  imports = [
    ./chromebook/audio.nix
    ./chromebook/power.nix
    ./chromebook/input.nix
  ];
}
