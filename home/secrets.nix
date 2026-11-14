# User-facing agenix secret distribution via Home Manager.
# System activation (`modules/nixos/secrets.nix`) decrypts secrets once using the
# root-owned `/etc/agenix/master.key` into `/run/agenix/*` with `owner = "mitac"`,
# keeping the master key out of user space while wiring SSH keys, `gh` auth, and
# API environment variables cleanly into `/home/mitac`.
{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:

let
  ageSecrets = if osConfig != null then (osConfig.age.secrets or { }) else { };
  secretsDir = ../secrets;
  hasBuilderSecret = ageSecrets ? "id-wsl-builder-user";
  hasPersonalSshSecret = ageSecrets ? "id-ed25519";
  hasAnySshSecret = hasBuilderSecret || hasPersonalSshSecret;
  hasGhHostsSecret = ageSecrets ? "gh-hosts.yml";
  hasUserEnvSecret = ageSecrets ? "user-env";
  hasAdbKeySecret = ageSecrets ? "adbkey";
  hasOpenCodeServiceSecret = ageSecrets ? "opencode-service.json";

  importUserEnvScript = pkgs.writeShellScript "mitac-import-user-env" ''
    set -eu
    env_file=${lib.escapeShellArg (if hasUserEnvSecret then ageSecrets."user-env".path else "")}
    if [ ! -r "$env_file" ]; then
      exit 0
    fi
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a

    mapfile -t var_names < <(
      ${pkgs.gnused}/bin/sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p' "$env_file"
    )
    if [ "''${#var_names[@]}" -gt 0 ]; then
      ${pkgs.systemd}/bin/systemctl --user import-environment "''${var_names[@]}" || true
    fi
  '';
in
{
  home.activation.ensureSshDir = lib.mkIf hasAnySshSecret (
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      ${pkgs.coreutils}/bin/install -d -m 700 "${config.home.homeDirectory}/.ssh"
    ''
  );

  home.activation.ensureAndroidDir = lib.mkIf hasAdbKeySecret (
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      ${pkgs.coreutils}/bin/install -d -m 750 "${config.home.homeDirectory}/.android"
    ''
  );

  home.file = lib.mkMerge [
    (lib.optionalAttrs hasBuilderSecret {
      ".ssh/id_wsl_builder".source =
        config.lib.file.mkOutOfStoreSymlink
          ageSecrets."id-wsl-builder-user".path;
    })
    (lib.optionalAttrs (hasBuilderSecret && builtins.pathExists (secretsDir + "/id-wsl-builder.pub")) {
      ".ssh/id_wsl_builder.pub".source = secretsDir + "/id-wsl-builder.pub";
    })
    (lib.optionalAttrs hasPersonalSshSecret {
      ".ssh/id_ed25519".source = config.lib.file.mkOutOfStoreSymlink ageSecrets."id-ed25519".path;
    })
    (lib.optionalAttrs (hasPersonalSshSecret && builtins.pathExists (secretsDir + "/id-ed25519.pub")) {
      ".ssh/id_ed25519.pub".source = secretsDir + "/id-ed25519.pub";
    })
    (lib.optionalAttrs hasAdbKeySecret {
      ".android/adbkey".source = config.lib.file.mkOutOfStoreSymlink ageSecrets."adbkey".path;
    })
    (lib.optionalAttrs (hasAdbKeySecret && builtins.pathExists (secretsDir + "/adbkey.pub")) {
      ".android/adbkey.pub".source = secretsDir + "/adbkey.pub";
    })
  ];

  xdg.configFile = lib.mkMerge [
    (lib.optionalAttrs hasGhHostsSecret {
      "gh/hosts.yml".source = config.lib.file.mkOutOfStoreSymlink ageSecrets."gh-hosts.yml".path;
    })
    (lib.optionalAttrs hasOpenCodeServiceSecret {
      "opencode/service.json".source =
        config.lib.file.mkOutOfStoreSymlink
          ageSecrets."opencode-service.json".path;
    })
  ];

  programs.bash.initExtra = lib.mkIf hasUserEnvSecret ''
    if [ -r ${lib.escapeShellArg ageSecrets."user-env".path} ]; then
      set -a
      # shellcheck disable=SC1091
      . ${lib.escapeShellArg ageSecrets."user-env".path}
      set +a
    fi
  '';

  systemd.user.services.mitac-agenix-user-env = lib.mkIf hasUserEnvSecret {
    Unit = {
      Description = "Import agenix user-env variables into systemd user session";
      After = [ "graphical-session-pre.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${importUserEnvScript}";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
