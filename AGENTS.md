# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **NixOS system-configuration flake** (host/user `mitac`, multi-session
greetd desktop — Sway (primary) / Plasma / GNOME / Xfce / Hyprland — with ASUS CX5500FE
"delbin" Chromebook support on `main`). It is **not** a long-running app/server: "running" it
means evaluating and building the system configuration with Nix. Applying it for real
(`sudo nixos-rebuild switch --flake .#mitac`) only works on the actual target NixOS
machine — see `README.md`.

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
- Full configuration check / toplevel (works when hardware-configuration.nix is real):
  `nix flake check`
  `nix build .#nixosConfigurations.mitac.config.system.build.toplevel`
- Lint / format (this repo follows nixfmt RFC style):
  `nix run nixpkgs#nixfmt -- --check flake.nix hosts/mitac/*.nix modules/nixos/*.nix modules/nixos/chromebook/*.nix modules/nixos/greetd/*.nix home/*.nix home/sessions/*.nix`
  (includes `modules/nixos/release.nix` for generation labels / git-tag workflow)
  (drop `--check` to reformat in place).

### Known gotchas (durable)

- `hosts/mitac/hardware-configuration.nix` in this repo is the **delbin machine's generated
  config** (real `fileSystems` / boot modules). Cloning onto another machine still requires
  regenerating and replacing that file before `nixos-rebuild switch` (see `README.md`).
- Chromebook ALSA UCM merge in `modules/nixos/chromebook/audio.nix` copies from read-only
  `/nix/store` inputs with `cp -a --no-preserve=mode` so the tree stays writable.
- Graphify CLI (`graphify`) is optional for agents; install with
  `nix run nixpkgs#uv -- tool install graphifyy` then `export PATH="$HOME/.local/bin:$PATH"`.
  After code edits: `graphify update .`

### Branch workflow

Do all work on `main` (commits, PRs). Do not develop on `chromebook`. See
`.cursor/rules/branch-workflow.mdc`.
