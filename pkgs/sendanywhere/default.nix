{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libnotify,
  libsecret,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libxcb,
  nss,
  nspr,
  pango,
  systemd,
}:

stdenv.mkDerivation {
  pname = "sendanywhere";
  version = "24.6.1";

  src = fetchurl {
    # Upstream publishes only a rolling "latest" URL; hash pins the contents.
    url = "https://update.send-anywhere.com/linux_downloads/sendanywhere_latest_amd64.deb";
    hash = "sha256-v1dV9tAaT5Lf5/9oKFWt9ckzophjZlDIMlNV6TcAl3w=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libgbm
    libnotify
    libsecret
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    libxcb
    nss
    nspr
    pango
    systemd
    stdenv.cc.cc
  ];

  # Bundled Electron; wrap only the launcher we create.
  dontWrapGApps = true;
  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt/sendanywhere $out/bin $out/share
    cp -a "opt/Send Anywhere/." $out/opt/sendanywhere/
    cp -a usr/share/. $out/share/

    chmod +x $out/opt/sendanywhere/SendAnywhere
    chmod +x $out/opt/sendanywhere/chrome_crashpad_handler || true

    substituteInPlace $out/share/applications/SendAnywhere.desktop \
      --replace-fail 'Exec="/opt/Send Anywhere/SendAnywhere" %U' 'Exec=sendanywhere %U'

    makeWrapper $out/opt/sendanywhere/SendAnywhere $out/bin/sendanywhere \
      "''${gappsWrapperArgs[@]}" \
      --prefix LD_LIBRARY_PATH : "$out/opt/sendanywhere" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

    runHook postInstall
  '';

  meta = {
    description = "Multi-platform file sharing service (Send Anywhere)";
    homepage = "https://send-anywhere.com";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "sendanywhere";
  };
}
