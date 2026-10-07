{
  lib,
  symlinkJoin,
  writeShellApplication,
  makeDesktopItem,
  stdenvNoCC,
  nodejs_24,
  chromium,
  curl,
  coreutils,
  procps,
}:

let
  # Internal CLI used by the GUI launcher (first run installs under ~/.local/share).
  dsh = writeShellApplication {
    name = "dsh";
    runtimeInputs = [ nodejs_24 ];
    text = ''
      export NPM_CONFIG_CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/npm"
      prefix="''${XDG_DATA_HOME:-$HOME/.local/share}/deepseek-harness"
      bin="$prefix/bin/dsh"
      if [ ! -x "$bin" ]; then
        mkdir -p "$prefix"
        npm install --prefix "$prefix" --no-fund --no-audit @deepseek-ai/dsh@0.2.0-rc.2
      fi
      exec "$bin" "$@"
    '';
  };

  gui = writeShellApplication {
    name = "deepseek-harness";
    runtimeInputs = [
      dsh
      chromium
      curl
      coreutils
      procps
    ];
    text = ''
      host=127.0.0.1
      port=3080
      url="http://''${host}:''${port}"
      profile="''${XDG_CONFIG_HOME:-$HOME/.config}/deepseek-harness-app"

      if ! curl -sf -o /dev/null --connect-timeout 1 "$url/"; then
        # Detach so closing the Chromium window does not kill the harness.
        nohup dsh web --host "$host" --port "$port" --no-open \
          >"''${XDG_STATE_HOME:-$HOME/.local/state}/deepseek-harness-web.log" 2>&1 &
        for _ in $(seq 1 90); do
          if curl -sf -o /dev/null --connect-timeout 1 "$url/"; then
            break
          fi
          sleep 0.5
        done
      fi

      if ! curl -sf -o /dev/null --connect-timeout 1 "$url/"; then
        printf 'deepseek-harness: web UI did not start at %s\n' "$url" >&2
        printf 'see %s\n' "''${XDG_STATE_HOME:-$HOME/.local/state}/deepseek-harness-web.log" >&2
        exit 1
      fi

      mkdir -p "$profile"
      exec chromium \
        --user-data-dir="$profile" \
        --class=DeepSeekHarness \
        --app="$url"
    '';
  };

  desktop = makeDesktopItem {
    name = "deepseek-harness";
    desktopName = "DeepSeek Harness";
    genericName = "AI coding agent";
    comment = "DeepSeek Harness web UI";
    exec = "deepseek-harness";
    icon = "deepseek-harness";
    categories = [ "Development" ];
    startupWMClass = "DeepSeekHarness";
  };

  icon = stdenvNoCC.mkDerivation {
    name = "deepseek-harness-icon";
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/share/icons/hicolor/scalable/apps
      cat > $out/share/icons/hicolor/scalable/apps/deepseek-harness.svg <<'EOF'
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
        <rect width="64" height="64" rx="14" fill="#0f172a"/>
        <circle cx="32" cy="28" r="14" fill="#4f8cff"/>
        <path d="M18 48c4-8 10-12 14-12s10 4 14 12" fill="none" stroke="#94a3b8" stroke-width="4" stroke-linecap="round"/>
      </svg>
      EOF
    '';
  };
in
symlinkJoin {
  name = "deepseek-harness";
  paths = [
    dsh
    gui
    desktop
    icon
  ];
  meta = {
    description = "DeepSeek Harness GUI (Chromium app window + local web UI)";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = lib.licenses.mit;
    mainProgram = "deepseek-harness";
    platforms = lib.platforms.linux;
  };
}
