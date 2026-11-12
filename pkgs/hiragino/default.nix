{
  lib,
  stdenvNoCC,
  src,
}:

stdenvNoCC.mkDerivation {
  pname = "hiragino-fonts";
  # Local proprietary OTFs. Not a flake input: modules/nixos/common.nix passes
  # src only when the directory exists under an impure eval.
  version = "local";

  inherit src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/fonts/opentype/hiragino"
    find "$src" -type f -iname '*.otf' -exec cp -t "$out/share/fonts/opentype/hiragino" {} +
    runHook postInstall
  '';

  meta = {
    description = "Hiragino Japanese font family (local proprietary)";
    license = lib.licenses.unfree;
    platforms = lib.platforms.all;
    hydraPlatforms = [ ];
  };
}
