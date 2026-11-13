# Scripts that used to be started as ~/MySettings/scripts/... are installed
# into the Nix store. Commands that must edit or build the checkout receive
# mitac.repoPath (default: lib/machine.nix).
{
  config,
  lib,
  pkgs,
  flakeTarget ? null,
  ...
}:
let
  machine = import ../lib/machine.nix;
  repoPath = config.mitac.repoPath;

  pyBin =
    name: file:
    pkgs.writers.writePython3Bin name {
      libraries = [ ];
      # These scripts already run on the machine. flake8 (line length and
      # friends) is not a reason for nixos-rebuild to fail.
      doCheck = false;
    } (builtins.readFile file);

  waybarAiStatus = pyBin "waybar-ai-status" ../scripts/waybar-ai-status.py;
  flakeUpdateCheckPy = pyBin "flake-update-check-flake" ../scripts/flake-update-check-flake.py;

  wrap =
    name: runtimeInputs: script:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = ''
        export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
        export FLAKE_CHECK_PY=${lib.escapeShellArg (lib.getExe flakeUpdateCheckPy)}
        exec ${pkgs.bash}/bin/bash ${script} ${lib.escapeShellArg repoPath} "$@"
      '';
    };

  netTools = [
    pkgs.cacert
    pkgs.coreutils
    pkgs.curl
    pkgs.gawk
    pkgs.gnused
    pkgs.nix
    pkgs.python3
  ];

  flakeUpdate = wrap "flake-update" netTools ../scripts/flake-update.sh;
  flakeUpdateCursor = wrap "flake-update-cursor" [
    pkgs.coreutils
    pkgs.nix
  ] ../scripts/flake-update-cursor.sh;
  flakeUpdateCheck = wrap "flake-update-check" (
    netTools ++ [ pkgs.procps ]
  ) ../scripts/flake-update-check.sh;
in
{
  options.mitac.repoPath = lib.mkOption {
    type = lib.types.str;
    default = machine.repoPath;
    description = ''
      Working copy of this flake. rebuild and flake-update run Nix against
      this directory. Change the default in lib/machine.nix.
    '';
  };

  options.mitac.flakeHost = lib.mkOption {
    type = lib.types.str;
    default = if flakeTarget != null then flakeTarget else machine.flakeHost;
    description = "nixosConfigurations name appended by rebuild.";
  };

  options.mitac.scripts = lib.mkOption {
    type = lib.types.attrsOf lib.types.package;
    internal = true;
    default = { };
    description = "Checkout scripts packaged into the Nix store.";
  };

  config = {
    mitac.scripts = {
      inherit
        flakeUpdate
        flakeUpdateCursor
        flakeUpdateCheck
        waybarAiStatus
        ;
    };

    home.packages = [
      flakeUpdate
      flakeUpdateCursor
      flakeUpdateCheck
      waybarAiStatus
    ];
  };
}
