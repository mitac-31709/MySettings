{
  lib,
  writeShellApplication,
  nodejs_24,
}:

# Upstream is still developer-preview; the nixpkgs packaging PR is not merged.
# Ship a Node + npx launcher pinned to a known npm release (network on first run).
writeShellApplication {
  name = "dsh";
  runtimeInputs = [ nodejs_24 ];
  text = ''
    export NPM_CONFIG_CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/npm"
    # Prefer a user-local install so later runs avoid re-resolving the registry.
    prefix="''${XDG_DATA_HOME:-$HOME/.local/share}/deepseek-harness"
    bin="$prefix/bin/dsh"
    if [ ! -x "$bin" ]; then
      mkdir -p "$prefix"
      npm install --prefix "$prefix" --no-fund --no-audit @deepseek-ai/dsh@0.2.0-rc.2
    fi
    exec "$bin" "$@"
  '';
  meta = {
    description = "DeepSeek Harness (dsh) launcher via npm @deepseek-ai/dsh";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = lib.licenses.mit;
    mainProgram = "dsh";
    platforms = lib.platforms.linux;
  };
}
