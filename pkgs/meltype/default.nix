{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  unzip,
  cmake,
  pkg-config,
  fcitx5,
  autoPatchelfHook,
  patchelf,
  icu,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "meltype";
  version = "1.2.1";

  # Rebuild the small fcitx5 addon so MELTYPE_DIR points into the Nix store.
  # NativeAOT core + Mozc helper come from the official Linux release zip.
  src = fetchFromGitHub {
    owner = "yksr-melt";
    repo = "Meltype";
    rev = "v${finalAttrs.version}";
    hash = "sha256-yI3wd5SEmtpCw97StXTzHGPk4poUpfBjWyB9qV5jr4s=";
  };

  binaryZip = fetchurl {
    url = "https://github.com/yksr-melt/Meltype/releases/download/v${finalAttrs.version}/Meltype-${finalAttrs.version}-linux.zip";
    hash = "sha256-43fr1Kms702XkCQcctmW4lxWTUm4naXAOZUAK030s1g=";
  };

  nativeBuildInputs = [
    unzip
    cmake
    pkg-config
    autoPatchelfHook
    patchelf
  ];

  buildInputs = [
    fcitx5
    icu
    stdenv.cc.cc.lib
  ];

  # NativeAOT dlopens libicu; fcitx5-with-addons reads this for LD_LIBRARY_PATH.
  passthru.extraLdLibraries = [ icu ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    cmake -S linux/fcitx5 -B build-fcitx5 \
      -DMELTYPE_DIR=${placeholder "out"}/lib/meltype \
      -DCMAKE_BUILD_TYPE=Release
    cmake --build build-fcitx5
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p \
      $out/lib/fcitx5 \
      $out/lib/meltype/mozc \
      $out/share/fcitx5/addon \
      $out/share/fcitx5/inputmethod \
      $out/share/licenses/meltype

    install -Dm555 build-fcitx5/meltype.so $out/lib/fcitx5/meltype.so
    install -Dm444 linux/fcitx5/meltype-addon.conf $out/share/fcitx5/addon/meltype.conf

    unzip -q ${finalAttrs.binaryZip} -d binary
    install -Dm555 binary/Meltype-linux/libMeltypeNative.so $out/lib/meltype/libMeltypeNative.so
    install -Dm555 binary/Meltype-linux/mozc/meltype_mozc_helper $out/lib/meltype/mozc/meltype_mozc_helper
    install -Dm444 binary/Meltype-linux/icon.png $out/lib/meltype/icon.png
    install -Dm444 binary/Meltype-linux/LICENSE $out/share/licenses/meltype/LICENSE
    install -Dm444 binary/Meltype-linux/THIRD-PARTY-NOTICES.md $out/share/licenses/meltype/THIRD-PARTY-NOTICES.md
    install -Dm444 binary/Meltype-linux/mozc/MOZC-LICENSE.txt $out/share/licenses/meltype/MOZC-LICENSE.txt

    substitute linux/fcitx5/meltype.conf $out/share/fcitx5/inputmethod/meltype.conf \
      --replace-fail '@DIR@' "$out/lib/meltype"

    runHook postInstall
  '';

  # .NET NativeAOT looks up ICU via dlopen (not DT_NEEDED); keep RPATH on the .so.
  postFixup = ''
    patchelf --add-rpath ${lib.makeLibraryPath [ icu ]} \
      $out/lib/meltype/libMeltypeNative.so
  '';

  meta = {
    description = "Japanese IME that mixes romaji Japanese and English (Fcitx5 addon)";
    homepage = "https://github.com/yksr-melt/Meltype";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    platforms = [ "x86_64-linux" ];
  };
})
