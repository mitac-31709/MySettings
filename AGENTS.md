# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **NixOS system-configuration flake** (host/user `mitac`, KDE Plasma desktop,
ASUS CX5500FE "delbin" Chromebook support on `main`). It is **not** a long-running
app/server: "running" it means evaluating and building the system configuration with Nix.
Applying it for real (`sudo nixos-rebuild switch --flake .#mitac`) only works on the actual
target NixOS machine — see `README.md`.

### Using Nix in the cloud VM (non-obvious)

Nix (Determinate Nix, flakes enabled) is installed in the VM snapshot in **daemonless mode**
(the pod has no systemd). Two things are needed once per VM boot before any `nix` command:

1. Start the Nix daemon (nothing auto-starts it without systemd). Run it in the background,
   e.g. in a tmux session:
   `sudo /nix/var/nix/profiles/default/bin/nix-daemon &`
2. Load Nix onto `PATH` in the current shell:
   `. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`

If `nix` commands report `cannot connect to socket at '/nix/var/nix/daemon-socket/socket'`,
the daemon is not running — do step 1.

### Develop / lint / build / eval

- Evaluate composed options (fast sanity check that all modules load):
  `nix eval .#nixosConfigurations.mitac.config.networking.hostName`
- Build a repo-declared package end-to-end (headline "included software"):
  `nix build .#nixosConfigurations.mitac.config.home-manager.users.mitac.programs.neovim.finalPackage`
- Lint / format (this repo follows nixfmt RFC style):
  `nix run nixpkgs#nixfmt -- --check flake.nix hosts/mitac/*.nix modules/nixos/*.nix home/mitac.nix`
  (includes `modules/nixos/release.nix` for generation labels / git-tag workflow)
  (drop `--check` to reformat in place).

### Known gotchas (durable)

- `nix flake check` and any full `system.build.toplevel` build **fail by design** here because
  `hosts/mitac/hardware-configuration.nix` is a placeholder stub (no `fileSystems` / `boot.loader`).
  The evaluation still exercises every module before hitting those assertions. A real build
  requires the target machine's generated hardware config (README shows how).
- `modules/nixos/chromebook.nix` builds `alsa-ucm-conf-chromebook` via `pkgs.runCommand` using
  `cp -a` from read-only `/nix/store` inputs; `cp -a` preserves the read-only mode, so the
  second copy fails with `Permission denied`. This blocks that derivation (and thus a full
  toplevel build) even with a valid hardware config. A fix would make the copied tree writable
  (e.g. `chmod -R u+w` after the first copy, or `cp --no-preserve=mode`).

### Branch workflow

Do all work on `main` (commits, PRs). Do not develop on `chromebook`. See
`.cursor/rules/branch-workflow.mdc`.
