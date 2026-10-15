{
  lib,
  stdenv,
  src,
  version,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libGL,
  libnotify,
  libsecret,
  libuuid,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libXScrnSaver,
  libXtst,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  udev,
  vulkan-loader,
}:

stdenv.mkDerivation {
  pname = "grok-bot";
  inherit version src;

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libgbm
    libGL
    libnotify
    libsecret
    libuuid
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    libXScrnSaver
    libXtst
    mesa
    nspr
    nss
    pango
    systemd
    udev
    vulkan-loader
  ];

  # ANGLE loads libEGL via dlopen.
  runtimeDependencies = [ libGL ];

  dontBuild = true;
  dontConfigure = true;
  dontStrip = true;

  autoPatchelfIgnoreMissingDeps = [
    "libc.musl-x86_64.so.1"
    # Optional Qt shims for KDE detection only.
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libQt6Core.so.6"
    "libQt6Gui.so.6"
    "libQt6Widgets.so.6"
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin $out/share
    # Upstream path has a space ("Grok Bot"); copy without it so Electron
    # chrome-sandbox / userns fallbacks stay reliable on NixOS.
    cp -a "opt/Grok Bot" $out/lib/grok-bot
    cp -a usr/share/. $out/share/

    makeWrapper $out/lib/grok-bot/grok-bot $out/bin/grok-bot \
      --prefix LD_LIBRARY_PATH : "$out/lib/grok-bot" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

    substituteInPlace $out/share/applications/grok-bot.desktop \
      --replace-fail 'Exec=grok-bot %U' 'Exec=grok-bot %U'

    runHook postInstall
  '';

  meta = {
    description = "Grok Bot desktop agent";
    homepage = "https://cursor.com/download/bot";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "grok-bot";
  };
}
