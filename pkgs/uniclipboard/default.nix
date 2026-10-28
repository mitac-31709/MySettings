{
  lib,
  stdenv,
  src,
  version,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook4,
  dbus,
  glib,
  gtk4,
  gtk4-layer-shell,
  libayatana-appindicator,
  libsoup_3,
  openssl,
  webkitgtk_6_0,
  libx11,
}:

stdenv.mkDerivation {
  pname = "uniclipboard";
  inherit version src;

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook4
  ];

  buildInputs = [
    dbus
    glib
    gtk4
    gtk4-layer-shell
    libayatana-appindicator
    libsoup_3
    openssl
    webkitgtk_6_0
    libx11
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
    # Keep the real argv0/exe name `uniclipd`. The GUI probes /proc/<pid>/exe and
    # rejects wrapped names like `.uniclipd-wrapped` as a stale/mismatched daemon.
    install -Dm755 usr/bin/uniclipd $out/bin/uniclipd
    cp -a usr/share/. $out/share/

    wrapProgram $out/bin/uniclipboard \
      "''${gappsWrapperArgs[@]}" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          gtk4-layer-shell
          libayatana-appindicator
        ]
      }" \
      --set-default WEBKIT_DISABLE_DMABUF_RENDERER 1

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
