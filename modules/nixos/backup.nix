# Encrypted backup of the user's home to Google Drive.
#
# Pieces:
#   - restic  : encrypted, deduplicated, snapshot-based backup engine.
#   - rclone  : Google Drive backend (restic talks to the "gdrive" remote).
#   - rbw     : CLI Bitwarden client. The restic repository password (i.e. the
#               encryption key) is stored in Bitwarden and fetched at runtime via
#               `rbw get`, so no key material lives on disk or in the Nix store.
#
# What is declarative (this file) vs. manual (secrets, kept out of the store):
#   declarative : which paths, excludes, schedule, retention, the Google Drive
#                 target, and that the key comes from Bitwarden.
#   manual      : the rclone OAuth token for Google Drive and the Bitwarden login.
# See README.md → "Encrypted /home backup" for the one-time setup.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  user = "mitac";
  uid = toString config.users.users.${user}.uid;

  # Google Drive destination: rclone remote "gdrive" plus a subpath. The remote
  # is configured out-of-band with `rclone config` (interactive OAuth).
  repository = "rclone:gdrive:restic/mitac-home";

  # rclone config holding the Google Drive OAuth token. Kept outside the Nix
  # store, readable by the backup user. Created with `rclone config`.
  rcloneConfigFile = "/home/${user}/.config/rclone/rclone.conf";

  # Bitwarden item whose password field holds the restic encryption key.
  bitwardenItem = "restic-home";

  # Wrapper so systemd's minimal PATH still finds rbw-agent, and the user
  # session socket under XDG_RUNTIME_DIR is reachable.
  resticPasswordCommand = pkgs.writeShellScript "restic-home-password" ''
    export PATH="${lib.makeBinPath [ pkgs.rbw ]}:$PATH"
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/${uid}}"
    exec ${lib.getExe pkgs.rbw} get ${bitwardenItem}
  '';

  # Non-secret: only tells restic to ask Bitwarden (via rbw) for the password.
  # Safe to keep in the Nix store — it contains no key material.
  resticEnvFile = pkgs.writeText "restic-home.env" ''
    RESTIC_PASSWORD_COMMAND=${resticPasswordCommand}
  '';
in
{
  environment.systemPackages = with pkgs; [
    restic
    rclone
    rbw
  ];

  services.restic.backups.home = {
    inherit user repository rcloneConfigFile;

    # The user's data under /home. On this single-user host this is effectively
    # all of /home. To back up every user's home, run as root instead and point
    # rclone/rbw at root's config.
    paths = [ "/home/${user}" ];

    # Skip caches, trash and large regenerable build artifacts.
    exclude = [
      "/home/${user}/.cache"
      "/home/${user}/.local/share/Trash"
      "/home/${user}/.mozilla/firefox/*/storage"
      "/home/${user}/**/node_modules"
      "/home/${user}/**/.direnv"
      "/home/${user}/**/target"
      "/home/${user}/.local/state/nvim/swap"
    ];

    # Provides RESTIC_PASSWORD_COMMAND → key stays in Bitwarden.
    environmentFile = "${resticEnvFile}";

    # Create the restic repository on Google Drive on first run.
    initialize = true;

    # Retention: prune old snapshots after each run.
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
    ];

    # Run daily; catch up if the machine was powered off at the scheduled time.
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };

    # createWrapper defaults to true → installs a `restic-home` command with the
    # same environment (repository, rclone config, Bitwarden password command) so
    # you can list snapshots or restore without re-specifying anything, e.g.:
    #   restic-home snapshots
    #   restic-home restore latest --target /tmp/restore
  };

  # Systemd's default PATH for this unit does not include profile bins; restic
  # needs rclone on PATH, and rbw needs rbw-agent. Also point at the logged-in
  # user's runtime dir so rbw can talk to an unlocked agent.
  systemd.services.restic-backups-home = {
    path = [
      pkgs.rbw
      pkgs.rclone
      pkgs.openssh
    ];
    serviceConfig = {
      Environment = [ "XDG_RUNTIME_DIR=/run/user/${uid}" ];
    };
  };
}
