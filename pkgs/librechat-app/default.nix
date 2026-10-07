{
  lib,
  symlinkJoin,
  writeShellApplication,
  makeDesktopItem,
  stdenvNoCC,
  chromium,
  curl,
  coreutils,
}:

let
  gui = writeShellApplication {
    name = "librechat";
    runtimeInputs = [
      chromium
      curl
      coreutils
    ];
    text = ''
      url=http://127.0.0.1:3081
      profile="''${XDG_CONFIG_HOME:-$HOME/.config}/librechat-app"

      if ! curl -sf -o /dev/null --connect-timeout 2 "$url/"; then
        printf 'librechat: server not reachable at %s\n' "$url" >&2
        printf 'check: systemctl status librechat mongodb\n' >&2
        exit 1
      fi

      mkdir -p "$profile"
      exec chromium \
        --user-data-dir="$profile" \
        --class=LibreChat \
        --app="$url"
    '';
  };

  desktop = makeDesktopItem {
    name = "librechat";
    desktopName = "LibreChat";
    genericName = "AI chat";
    comment = "Local LibreChat UI";
    exec = "librechat";
    icon = "librechat";
    categories = [ "Network" ];
    startupWMClass = "LibreChat";
  };

  icon = stdenvNoCC.mkDerivation {
    name = "librechat-icon";
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/share/icons/hicolor/scalable/apps
      cat > $out/share/icons/hicolor/scalable/apps/librechat.svg <<'EOF'
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
        <rect width="64" height="64" rx="14" fill="#111827"/>
        <rect x="12" y="16" width="40" height="28" rx="8" fill="#10b981"/>
        <circle cx="24" cy="30" r="3" fill="#111827"/>
        <circle cx="32" cy="30" r="3" fill="#111827"/>
        <circle cx="40" cy="30" r="3" fill="#111827"/>
        <path d="M28 44 L32 52 L36 44" fill="#10b981"/>
      </svg>
      EOF
    '';
  };
in
symlinkJoin {
  name = "librechat-app";
  paths = [
    gui
    desktop
    icon
  ];
  meta = {
    description = "LibreChat GUI launcher (Chromium app window)";
    homepage = "https://www.librechat.ai/";
    license = lib.licenses.mit;
    mainProgram = "librechat";
    platforms = lib.platforms.linux;
  };
}
