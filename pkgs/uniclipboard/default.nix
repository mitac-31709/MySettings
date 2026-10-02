{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  cairo,
  dbus,
  gdk-pixbuf,
  glib,
  gtk3,
  gtk-layer-shell,
  libayatana-appindicator,
  libsoup_3,
  openssl,
  webkitgtk_4_1,
}:

stdenv.mkDerivation rec {
  pname = "uniclipboard";
  version = "1.0.1";

  src = fetchurl {
    url = "https://github.com/UniClipboard/UniClipboard/releases/download/v${version}/UniClipboard_${version}_amd64.deb";
    hash = "sha256-f2jw4Gk/JXDdw/jkmNb4rOxwteTxj51nThcEa5XbFjA=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    cairo
    dbus
    gdk-pixbuf
    glib
    gtk3
    gtk-layer-shell
    libayatana-appindicator
    libsoup_3
    openssl
    webkitgtk_4_1
    stdenv.cc.cc
  ];

  # Tauri GUI; wrap only the launchers we create.
  dontWrapGApps = true;
  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share
    install -Dm755 usr/bin/uniclipboard $out/bin/uniclipboard
    install -Dm755 usr/bin/uniclipd $out/bin/uniclipd
    cp -a usr/share/. $out/share/

    wrapProgram $out/bin/uniclipboard \
      "''${gappsWrapperArgs[@]}" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
        gtk-layer-shell
        libayatana-appindicator
      ]}"
    wrapProgram $out/bin/uniclipd "''${gappsWrapperArgs[@]}"

    runHook postInstall
  '';

  meta = {
    description = "End-to-end encrypted clipboard sync across devices";
    homepage = "https://uniclipboard.app";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "uniclipboard";
  };
}
