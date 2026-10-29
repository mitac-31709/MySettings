{
  lib,
  python3,
  gtk3,
  gtk-layer-shell,
  gobject-introspection,
  wrapGAppsHook3,
  makeWrapper,
  pulseaudio,
  fetchurl,
}:

let
  # Windows Me system startup ("The Microsoft Sound", ~5.5s).
  # Same asset as therestartpage login.wav / guidebookgallery Me startup.
  windowsMeStartupWav = fetchurl {
    url = "http://www.therestartpage.com/OS/media/windows-me/login.wav";
    name = "windows-me-startup.wav";
    hash = "sha256-Z2rgH1Ft8MJ6H5sY7inmxawdEg57qggoLYefb7InWqE=";
  };
in
python3.pkgs.buildPythonApplication {
  pname = "ai-status-chips";
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
    install -Dm755 ai_status_chips.py $out/bin/ai-status-chips
    install -Dm644 ${windowsMeStartupWav} $out/share/ai-status-chips/windows-me-startup.wav
    runHook postInstall
  '';

  dontWrapGApps = true;
  preFixup = ''
    wrapProgram $out/bin/ai-status-chips \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ pulseaudio ]} \
      --set AI_STATUS_DONE_SOUND "$out/share/ai-status-chips/windows-me-startup.wav"
  '';

  meta = {
    description = "Sway hover chips for Waybar AI status (slide-in per agent)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ai-status-chips";
  };
}
