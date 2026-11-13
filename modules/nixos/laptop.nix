# Shared Intel laptop hardware stack (Chromebook and VAIO).
{ ... }:

{
  imports = [
    ./laptop/graphics.nix
    ./laptop/input.nix
    ./laptop/power.nix
  ];
}
