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
  libGL,
  libnotify,
  libusb1,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  mesa,
  nspr,
  nss,
  openssl,
  pango,
  systemd,
  vulkan-loader,
  xz,
}:

stdenv.mkDerivation {
  pname = "chatgpt";
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
    libGL
    libnotify
    libusb1
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    mesa
    nspr
    nss
    openssl
    pango
    systemd
    vulkan-loader
    xz
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
    # TPM optional (Secure Storage); ignore if not linked on this host.
    "libtss2-esys.so.0"
    "libtss2-mu.so.0"
    "libtss2-tcti-device.so.0"
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  # Codex copies bundled plugins into ~/.codex/.tmp preserving mode. Nix store
  # paths are finalized non-writable, so those copies stay 0444 → EACCES and
  # undeletable multi-GB staging that crashes the app. Mirror plugins into a
  # user-writable cache and set CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin $out/share
    cp -a usr/lib/chatgpt $out/lib/
    cp -a usr/share/. $out/share/

    pluginsSrc="$out/lib/chatgpt/resources/plugins"
    cat > $out/lib/chatgpt/prepare-bundled-plugins <<'PREPARE_EOF'
    #!/bin/bash
    set -euo pipefail
    pluginsSrc='@pluginsSrc@'
    res_cache="''${XDG_CACHE_HOME:-$HOME/.cache}/chatgpt-bundled-resources/@version@"
    if [[ ! -f "$res_cache/.sync-ok" ]]; then
      rm -rf "$res_cache"
      mkdir -p "$res_cache"
      cp -a --no-preserve=mode "$pluginsSrc" "$res_cache/plugins"
      chmod -R u+w "$res_cache"
      : >"$res_cache/.sync-ok"
    fi
    staging="''${CODEX_HOME:-$HOME/.codex}/.tmp/bundled-marketplaces"
    if [[ -d "$staging" ]]; then
      chmod -R u+w "$staging" 2>/dev/null || true
    fi
    export CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH="$res_cache"
    PREPARE_EOF
    sed -i 's/^    //' $out/lib/chatgpt/prepare-bundled-plugins
    substituteInPlace $out/lib/chatgpt/prepare-bundled-plugins \
      --replace-fail '@pluginsSrc@' "$pluginsSrc" \
      --replace-fail '@version@' ${lib.escapeShellArg version}
    chmod +x $out/lib/chatgpt/prepare-bundled-plugins

    makeWrapper $out/lib/chatgpt/ChatGPT $out/bin/chatgpt \
      --prefix LD_LIBRARY_PATH : "$out/lib/chatgpt" \
      --run "source '$out/lib/chatgpt/prepare-bundled-plugins'" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

    substituteInPlace $out/share/applications/chatgpt.desktop \
      --replace-fail 'Exec=chatgpt %U' 'Exec=chatgpt %U'

    runHook postInstall
  '';

  meta = {
    description = "Official ChatGPT desktop app (includes Codex)";
    homepage = "https://developers.openai.com/codex/app";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "chatgpt";
  };
}
