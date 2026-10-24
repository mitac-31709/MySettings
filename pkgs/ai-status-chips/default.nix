{
  lib,
  python3,
  gtk3,
  gtk-layer-shell,
  gobject-introspection,
  wrapGAppsHook3,
  makeWrapper,
}:

python3.pkgs.buildPythonApplication {
  pname = "ai-status-chips";
  version = "0.1.0";
  format = "other";

  src = ./.;

  dontBuild = true;
  dontConfigure = true;

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsHook3
    makeWrapper
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
    install -Dm755 ai_status_chips.py $out/bin/ai-status-chips
    runHook postInstall
  '';

  dontWrapGApps = true;
  preFixup = ''
    wrapProgram $out/bin/ai-status-chips "''${gappsWrapperArgs[@]}"
  '';

  meta = {
    description = "Sway hover chips for Waybar AI status (slide-in per agent)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ai-status-chips";
  };
}
