{
  lib,
  stdenv,
  src,
  version,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  nodejs,
  python3,
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
    python3
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

  # Two Nix-specific ChatGPT/Codex crashes on Linux:
  #
  # 1) SIGILL in node::GetNodeReport (thread "git"): autoPatchelf relocates
  #    PT_INTERP far past detect-libc's ~2KiB ELF scan, so familySync() falls
  #    back to process.report.getReport(), which hits Electron's CFI trap
  #    (openai/codex#38123, NixOS/nixpkgs#551713). Force glibc + skip report.
  # 2) EACCES / multi-GB undeletable plugin staging: store copies are 0444;
  #    mirror plugins to a writable cache via CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin $out/share
    cp -a usr/lib/chatgpt $out/lib/
    cp -a usr/share/. $out/share/

    # Length-preserving asar edits (asar header offsets must stay valid).
    asar="$out/lib/chatgpt/resources/app.asar"
    python3 - "$asar" <<'PY'
    import sys
    from pathlib import Path
    path = Path(sys.argv[1])
    data = path.read_bytes()
    replacements = [
        (b"const family = familySync();", b"const family = 'glibc' ;/**/"),
        (b"isLinux() && process.report", b"false /* nix:skip report */"),
    ]
    for old, new in replacements:
        if len(old) != len(new):
            raise SystemExit(f"length mismatch: {old!r} vs {new!r}")
        count = data.count(old)
        if count != 1:
            raise SystemExit(f"expected 1 occurrence of {old!r}, found {count}")
        data = data.replace(old, new, 1)
    path.write_bytes(data)
    PY

    pluginsSrc="$out/lib/chatgpt/resources/plugins"
    resourcesDir="$out/lib/chatgpt/resources"
    cat > $out/lib/chatgpt/prepare-bundled-plugins <<'PREPARE_EOF'
    #!/bin/bash
    set -euo pipefail
    pluginsSrc='@pluginsSrc@'
    resourcesDir='@resourcesDir@'
    res_cache="''${XDG_CACHE_HOME:-$HOME/.cache}/chatgpt-bundled-resources/@version@"
    if [[ ! -f "$res_cache/.sync-ok" ]]; then
      rm -rf "$res_cache"
      mkdir -p "$res_cache"
      # Drop store modes so the tree is writable, then restore +x from the
      # source (needed for Browser Use extension-host; --no-preserve=mode
      # otherwise leaves it non-executable and native messaging fails).
      cp -a --no-preserve=mode "$pluginsSrc" "$res_cache/plugins"
      chmod -R u+w "$res_cache"
      : >"$res_cache/.sync-ok"
    fi
    # Restore +x lost by --no-preserve=mode (paths have no newlines).
    while IFS= read -r rel; do
      [[ -z "$rel" ]] && continue
      target="$res_cache/plugins/$rel"
      if [[ -f "$target" ]]; then
        chmod u+x "$target" || true
      fi
    done < <(find "$pluginsSrc" -type f -executable -printf '%P\n' 2>/dev/null || true)
    staging="''${CODEX_HOME:-$HOME/.codex}/.tmp/bundled-marketplaces"
    if [[ -d "$staging" ]]; then
      chmod -R u+w "$staging" 2>/dev/null || true
    fi
    export CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH="$res_cache"

    # Official .deb installs Native Messaging hosts for Chromium browsers
    # (including Vivaldi). On NixOS the desktop installer often never runs
    # successfully (plugin +x lost; bundled node can SIGSEGV), so write the
    # same manifests the upstream installManifest.mjs would create.
    chrome_plugin="$res_cache/plugins/openai-bundled/plugins/chrome"
    extension_host="$chrome_plugin/extension-host/linux/x64/extension-host"
    if [[ -n "''${HOME:-}" && -f "$extension_host" ]]; then
      chmod u+x "$extension_host" || true
      host_dir="$(dirname "$extension_host")"
      # Single-line JSON (avoid under-indented lines that shrink Nix's common
      # indent and break the python <<'PY' terminator in installPhase).
      printf '%s\n' "{\"schemaVersion\":1,\"channel\":\"prod\",\"browserClientPath\":\"$chrome_plugin/scripts/browser-client.mjs\",\"codexCliPath\":\"$resourcesDir/codex\",\"nodePath\":\"$resourcesDir/cua_node/bin/node\",\"nodeReplPath\":\"$resourcesDir/cua_node/bin/node_repl\",\"proxyHost\":\"127.0.0.1\",\"proxyPort\":0}" >"$host_dir/extension-host-config.json"
      nmh_json="{\"allowed_origins\":[\"chrome-extension://hehggadaopoacecdllhhajmbjkdcmajg/\",\"chrome-extension://odlomjlbamekndcpllcnffbgeohgkmjh/\"],\"description\":\"ChatGPT browser native messaging host\",\"name\":\"com.openai.codexextension\",\"path\":\"$extension_host\",\"type\":\"stdio\"}"
      for nmh_dir in \
        "$HOME/.config/vivaldi/NativeMessagingHosts" \
        "$HOME/.config/google-chrome/NativeMessagingHosts" \
        "$HOME/.config/chromium/NativeMessagingHosts"; do
        mkdir -p "$nmh_dir"
        printf '%s\n' "$nmh_json" >"$nmh_dir/com.openai.codexextension.json"
      done
    fi
    PREPARE_EOF
    sed -i 's/^    //' $out/lib/chatgpt/prepare-bundled-plugins
    substituteInPlace $out/lib/chatgpt/prepare-bundled-plugins \
      --replace-fail '@pluginsSrc@' "$pluginsSrc" \
      --replace-fail '@resourcesDir@' "$resourcesDir" \
      --replace-fail '@version@' ${lib.escapeShellArg version}
    chmod +x $out/lib/chatgpt/prepare-bundled-plugins

    # ChatGPT's Electron defaults to X11 even with ozone-platform-hint=auto
    # (NIXOS_OZONE_WL). On Sway that means XWayland + XIM, where Meltype
    # composition is flaky. Force Wayland + text-input-v3 like Cursor.
    makeWrapper $out/lib/chatgpt/ChatGPT $out/bin/chatgpt \
      --prefix LD_LIBRARY_PATH : "$out/lib/chatgpt" \
      --run "source '$out/lib/chatgpt/prepare-bundled-plugins'" \
      --add-flags "\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-features=WaylandWindowDecorations --enable-wayland-ime=true --wayland-text-input-version=3}"

    substituteInPlace $out/share/applications/chatgpt.desktop \
      --replace-fail 'Exec=chatgpt %U' 'Exec=chatgpt %U'

    runHook postInstall
  '';

  # Bundled cua_node SIGSEGVs after autoPatchelf (dl_main) and also when
  # inheriting Electron's LD_LIBRARY_PATH=/lib/chatgpt. Point CUA at nixpkgs
  # node instead (same approach as code-cursor's helpers/node).
  postFixup = ''
    cuaBin="$out/lib/chatgpt/resources/cua_node/bin"
    if [[ -e "$cuaBin/node" ]]; then
      rm -f "$cuaBin/node"
      ln -s ${lib.getExe nodejs} "$cuaBin/node"
    fi
    if [[ -e "$cuaBin/node_repl" ]]; then
      rm -f "$cuaBin/node_repl"
      ln -s ${lib.getExe nodejs} "$cuaBin/node_repl"
    fi
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
