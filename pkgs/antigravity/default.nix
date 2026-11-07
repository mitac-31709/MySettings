# Google Antigravity CLI (`agy`).
#
# Same flat native build the https://antigravity.google/cli/install.sh script
# installs under ~/.local/bin/agy (manifest:
# antigravity-cli-auto-updater-…/manifests/linux_amd64.json).
#
# Do not autoPatchelf: the binary is built against the system loader and runs
# via NixOS /lib64/ld-linux-x86-64.so.2 (nix-ld), same approach as opencode.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "antigravity";
  version = "1.5.2";

  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.2-4951595792859136/linux-x64/cli_linux_x64.tar.gz";
    hash = "sha256-2mlqjcYSKmPV/73SGwLIpi1TYfug7X07wtJhmInmJxE=";
  };

  # Archive contains a single `antigravity` binary at the root.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 antigravity $out/bin/antigravity
    ln -s antigravity $out/bin/agy
    runHook postInstall
  '';

  meta = {
    description = "Google Antigravity terminal coding agent (CLI)";
    homepage = "https://antigravity.google/";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "agy";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
