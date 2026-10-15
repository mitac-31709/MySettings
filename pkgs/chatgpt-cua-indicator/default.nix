{
  lib,
  python3,
  gtk3,
  gtk-layer-shell,
  gobject-introspection,
  wrapGAppsHook3,
}:

python3.pkgs.buildPythonApplication {
  pname = "chatgpt-cua-indicator";
  version = "0.1.0";
  format = "other";

  src = ./.;

  dontBuild = true;
  dontConfigure = true;

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsHook3
  ];

  buildInputs = [
    gtk3
    gtk-layer-shell
  ];

  propagatedBuildInputs = with python3.pkgs; [
    pygobject3
    pycairo
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 chatgpt_cua_indicator.py $out/bin/chatgpt-cua-indicator
    runHook postInstall
  '';

  meta = {
    description = "Sway overlay when ChatGPT Computer Use is controlling the desktop";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "chatgpt-cua-indicator";
  };
}
