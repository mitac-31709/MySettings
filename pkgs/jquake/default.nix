# Sway/XWayland-friendly JQuake launcher over a pinned 1.8.4 zip.
#
# Upstream/nixpkgs issues we fix here:
# - AWT on tiling WMs paints a black main window without
#   `_JAVA_AWT_WM_NONREPARENTING=1`.
# - nixpkgs cds into a temp dir for errors.log but leaves `sounds/` behind,
#   so relative wav paths 404.
# - JVM flags were placed after `-jar` (passed to main, not HotSpot); Cloudflare
#   also 403s the default `Java/1.8` User-Agent on some APIs.
# - 1.8.4 prompts to update to 1.8.5 via https://jquake.net/version; we break
#   that check (same-length URL → 404) so the dialog never appears.
# - The JAR Class-Path is relative (`JQuake_lib/…`), so the patched JAR must
#   stay next to that directory (not in a separate store path).
{
  lib,
  jquake,
  fetchurl,
  jre8,
  unzip,
  zip,
  writeShellApplication,
  symlinkJoin,
  stdenvNoCC,
}:

let
  unwrapped = jquake.overrideAttrs (_old: {
    version = "1.8.4";
    src = fetchurl {
      url = "https://github.com/fleneindre/fleneindre.github.io/raw/master/downloads/JQuake_1.8.4_linux.zip";
      hash = "sha256-oIYkYmI8uG4zjnm1Jq1mzIcSwRlKbWJqvACygQyp9sA=";
    };
  });

  # Same-length swap so the constant-pool UTF-8 length stays valid.
  versionUrlOld = "https://jquake.net/version";
  versionUrlNew = "https://jquake.net/versiox";

  # Copy lib/ (jar + JQuake_lib + sounds) and replace only JQuake.jar.
  libDir = stdenvNoCC.mkDerivation {
    pname = "jquake-lib";
    inherit (unwrapped) version;
    nativeBuildInputs = [
      unzip
      zip
    ];
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out" work
      # Store inputs are read-only; drop mode so we can replace the jar.
      cp -a --no-preserve=mode ${unwrapped}/lib/. "$out/"
      cd work
      unzip -q "$out/JQuake.jar"
      # Disable update check (endpoint 404s; startup continues without the dialog).
      sed -i 's|${versionUrlOld}|${versionUrlNew}|' net/jquake/c/c.class
      rm -f "$out/JQuake.jar"
      zip -qr "$out/JQuake.jar" .
      runHook postInstall
    '';
  };

  launcher = writeShellApplication {
    name = "JQuake";
    runtimeInputs = [ jre8 ];
    text = ''
      export _JAVA_AWT_WM_NONREPARENTING="''${_JAVA_AWT_WM_NONREPARENTING:-1}"
      workdir="$(mktemp -d -p /tmp jquake-XXXXXX)"
      trap 'rm -rf "$workdir"' EXIT
      ln -sf "${libDir}/sounds" "$workdir/sounds"
      cd "$workdir"
      exec java \
        -Xmx200m -Xms32m -Xmn2m \
        -Djava.net.preferIPv4Stack=true \
        -Dhttp.agent='Mozilla/5.0 (X11; Linux x86_64) JQuake' \
        -jar "${libDir}/JQuake.jar" \
        "$@" > /dev/null
    '';
  };
in
symlinkJoin {
  name = "jquake-${unwrapped.version}";
  paths = [ unwrapped ];
  postBuild = ''
    rm -f "$out/bin/JQuake"
    ln -s ${lib.getExe launcher} "$out/bin/JQuake"
    ln -s JQuake "$out/bin/jquake"
  '';
  meta = unwrapped.meta // {
    description = "${unwrapped.meta.description or "JQuake"} (1.8.4, Sway fixes, no update prompt)";
    mainProgram = "JQuake";
  };
}
