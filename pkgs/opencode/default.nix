# OpenCode 2 CLI (anomalyco/opencode).
#
# nixpkgs `opencode` is still the 1.x line; the upstream V2 terminal client is
# published as `@opencode/cli-linux-x64` on npm (same binary the
# https://opencode.ai/v2/install script installs under ~/.opencode/bin).
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "opencode";
  version = "2.1.2";

  src = fetchurl {
    url = "https://registry.npmjs.org/@opencode/cli-linux-x64/-/cli-linux-x64-${finalAttrs.version}.tgz";
    hash = "sha256-LhxmX16C5TFzIynyoxBmcoc0d1BuN4sX0w7qvTHRObM=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  # npm pack layout: package/bin/opencode
  sourceRoot = "package";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/opencode $out/bin/opencode
    runHook postInstall
  '';

  meta = {
    description = "AI coding agent built for the terminal (OpenCode 2 CLI)";
    homepage = "https://github.com/anomalyco/opencode";
    changelog = "https://github.com/anomalyco/opencode/releases";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "opencode";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
