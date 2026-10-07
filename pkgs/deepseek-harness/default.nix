{
  lib,
  symlinkJoin,
  writeShellApplication,
  makeDesktopItem,
  stdenvNoCC,
  nodejs-official,
  chromium,
  curl,
  coreutils,
  gnused,
  procps,
}:

let
  nodeBin = "${nodejs-official}/bin/node";
  npmBin = "${nodejs-official}/bin/npm";

  # Internal CLI: install under ~/.local/share and run with official Node
  # (nixpkgs Node breaks node-addon-require-builtin on NixOS).
  dsh = writeShellApplication {
    name = "dsh";
    runtimeInputs = [
      coreutils
    ];
    text = ''
      export NPM_CONFIG_CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/npm"
      prefix="''${XDG_DATA_HOME:-$HOME/.local/share}/deepseek-harness"
      entry="$prefix/node_modules/@deepseek-ai/dsh/lib/bin.js"
      if [ ! -f "$entry" ]; then
        mkdir -p "$prefix"
        # Local prefix install puts bins under node_modules/.bin (not $prefix/bin).
        # Allow native install scripts (node-pty / koffi / spawn-helper).
        NPM_CONFIG_IGNORE_SCRIPTS=false \
          ${npmBin} install --prefix "$prefix" --no-fund --no-audit \
          @deepseek-ai/dsh@0.2.0-rc.2
      fi
      if [ ! -f "$entry" ]; then
        printf 'dsh: missing %s after npm install\n' "$entry" >&2
        exit 1
      fi
      # Prefer argv flag over native addon (also required for HMR on some builds).
      exec ${nodeBin} --expose-internals "$entry" "$@"
    '';
  };

  gui = writeShellApplication {
    name = "deepseek-harness";
    runtimeInputs = [
      dsh
      chromium
      curl
      coreutils
      gnused
      procps
    ];
    text = ''
      host=127.0.0.1
      port=3080
      profile="''${XDG_CONFIG_HOME:-$HOME/.config}/deepseek-harness-app"
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}"
      mkdir -p "$state_dir" "$profile"
      log="$state_dir/deepseek-harness-web.log"

      url=""
      # Reuse if port is up and the last log URL still answers (any HTTP status).
      if [[ -f "$log" ]] && curl -s -o /dev/null --connect-timeout 1 "http://''${host}:''${port}/"; then
        url="$(sed -n 's|^dsh web: \(http://[^ ]*\)|\1|p' "$log" | tail -n1 || true)"
      fi

      if [[ -z "$url" ]]; then
        : >"$log"
        # Detach so closing Chromium does not kill the harness.
        nohup dsh web --host "$host" --port "$port" --no-open >>"$log" 2>&1 &
        for _ in $(seq 1 120); do
          url="$(sed -n 's|^dsh web: \(http://[^ ]*\)|\1|p' "$log" | tail -n1 || true)"
          if [[ -n "$url" ]]; then
            break
          fi
          sleep 0.5
        done
      fi

      if [[ -z "$url" ]]; then
        printf 'deepseek-harness: web UI did not start (expected "dsh web: http://…" in log)\n' >&2
        printf 'see %s\n' "$log" >&2
        exit 1
      fi

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
