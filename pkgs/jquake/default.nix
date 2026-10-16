# Sway/XWayland-friendly JQuake launcher over nixpkgs' unpackaged zip.
#
# Upstream/nixpkgs issues we fix here:
# - AWT on tiling WMs paints a black main window without
#   `_JAVA_AWT_WM_NONREPARENTING=1`.
# - nixpkgs cds into a temp dir for errors.log but leaves `sounds/` behind,
#   so relative wav paths 404.
# - JVM flags were placed after `-jar` (passed to main, not HotSpot); Cloudflare
#   also 403s the default `Java/1.8` User-Agent on some APIs.
{
  lib,
  jquake,
  jre8,
  writeShellApplication,
  symlinkJoin,
}:

let
  unwrapped = jquake;

  launcher = writeShellApplication {
    name = "JQuake";
    runtimeInputs = [ jre8 ];
    text = ''
      export _JAVA_AWT_WM_NONREPARENTING="''${_JAVA_AWT_WM_NONREPARENTING:-1}"
      workdir="$(mktemp -d -p /tmp jquake-XXXXXX)"
      trap 'rm -rf "$workdir"' EXIT
      ln -sf "${unwrapped}/lib/sounds" "$workdir/sounds"
      cd "$workdir"
      exec java \
        -Xmx200m -Xms32m -Xmn2m \
        -Djava.net.preferIPv4Stack=true \
        -Dhttp.agent='Mozilla/5.0 (X11; Linux x86_64) JQuake' \
        -jar "${unwrapped}/lib/JQuake.jar" \
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
    mainProgram = "JQuake";
  };
}
