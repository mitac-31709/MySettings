{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

# Upstream nodejs.org binary (not nixpkgs source-built Node).
# DeepSeek Harness needs this: node-addon-require-builtin only matches
# official Node layouts; nixpkgs Node fails with Unsupported/no-getter.
stdenv.mkDerivation (finalAttrs: {
  pname = "nodejs-official";
  version = "24.21.0";

  src = fetchurl {
    url = "https://nodejs.org/dist/v${finalAttrs.version}/node-v${finalAttrs.version}-linux-x64.tar.xz";
    hash = "sha256-/Y5Z1aURUQ9qKYr7VI8Yx9KxvkBNi0on2U++SfVsstY=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -a . $out/
    runHook postInstall
  '';

  meta = {
    description = "Official Node.js binary distribution from nodejs.org";
    homepage = "https://nodejs.org/";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "node";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
