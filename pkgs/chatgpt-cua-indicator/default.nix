{
  lib,
  python3,
  gtk3,
  gtk-layer-shell,
  gobject-introspection,
  wrapGAppsHook3,
  makeWrapper,
  sway,
  wtype,
  procps,
}:

python3.pkgs.buildPythonApplication {
  pname = "chatgpt-cua-indicator";
  version = "0.2.0";
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
    install -Dm755 chatgpt_cua_indicator.py $out/bin/chatgpt-cua-indicator
    install -Dm755 agent-screen-stop $out/bin/agent-screen-stop
    runHook postInstall
  '';

  dontWrapGApps = true;
  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath [ sway wtype procps ]}
      --prefix PATH : $out/bin
    )
    wrapProgram $out/bin/chatgpt-cua-indicator "''${gappsWrapperArgs[@]}"
    wrapProgram $out/bin/agent-screen-stop \
      --prefix PATH : ${lib.makeBinPath [ sway wtype procps ]}
  '';

  meta = {
    description = "Sway overlay while ChatGPT/Cursor screen agents are controlling the desktop";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "chatgpt-cua-indicator";
  };
}
