{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  gobject-introspection,
  python3,
  ibus,
  gtk3,
  glib,
  icu,
  xdg-utils,
}:

let
  python = python3.withPackages (
    ps: with ps; [
      pygobject3
      (toPythonModule ibus)
    ]
  );
in
stdenv.mkDerivation rec {
  pname = "meltype";
  version = "1.0.0";

  src = fetchurl {
    url = "https://github.com/yksr-melt/Meltype/releases/download/v${version}/Meltype-${version}-linux.zip";
    hash = "sha256-fodkXiKgI+7EXBehkdd3gajGnlEu8ZHINxo+mWE1PEg=";
  };

  sourceRoot = "Meltype-linux";

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
    gobject-introspection
  ];

  buildInputs = [
    python
    ibus
    gtk3
    glib
    icu
    stdenv.cc.cc.lib
  ];

  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/meltype $out/share/ibus/component
    cp -a libMeltypeNative.so ibus-engine-meltype icon.png LICENSE THIRD-PARTY-NOTICES.md $out/lib/meltype/
    cp -a mozc $out/lib/meltype/
    chmod 755 $out/lib/meltype/ibus-engine-meltype $out/lib/meltype/mozc/meltype_mozc_helper

    substitute meltype.xml $out/share/ibus/component/meltype.xml \
      --replace-fail '@DIR@' "$out/lib/meltype"

    runHook postInstall
  '';

  postFixup = ''
    patchShebangs $out/lib/meltype/ibus-engine-meltype
    wrapProgram $out/lib/meltype/ibus-engine-meltype \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          icu
          stdenv.cc.cc.lib
        ]
      } \
      --prefix LD_LIBRARY_PATH : "$out/lib/meltype"
  '';

  meta = {
    isIbusEngine = true;
    description = "Japanese IME that mixes romaji Japanese and English without Hankaku/Zenkaku (IBus preview)";
    homepage = "https://github.com/yksr-melt/Meltype";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "ibus-engine-meltype";
  };
}
