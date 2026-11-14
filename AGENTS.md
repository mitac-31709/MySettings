# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **NixOS system-configuration flake** (user `mitac`, greetd + Sway
desktop, supporting ASUS CX5500FE "delbin" Chromebook as `.#chromebook` and Intel
8th+ gen VAIO laptops as `.#vaio` on `main`; `.#mitac` is kept as a legacy alias
for `.#chromebook`). It is **not** a long-running app/server: "running" it means
evaluating and building the system configuration with Nix. Applying it for real
(`sudo nixos-rebuild switch --flake .#chromebook` or `.#vaio`) only works on the
actual target NixOS machine — see `README.md`.

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

- Evaluate composed config (fast sanity check that all modules load):
  `nix eval .#nixosConfigurations.chromebook.config.networking.hostName`
  `nix eval .#nixosConfigurations.vaio.config.networking.hostName`
- **Do not** eval `.#nixosConfigurations.<host>.options…` (especially
  `options.home-manager.users`) — it forces the full options tree and stalls the
  machine. Prefer narrow `config.…` paths, or read HM/nixpkgs module sources with
  `rg` / file read. If an options attr is unavoidable, use a leaf path only and
  run under low priority:
  `nice -n 19 ionice -c3 nix eval '…'` (interactive: `nix-eval-low`).
- Build a repo-declared package end-to-end (headline "included software"):
  `nix build .#nixosConfigurations.vaio.config.home-manager.users.mitac.programs.neovim.finalPackage`
- Full configuration check / toplevel (works when `hardware-configuration.nix` matches the target):
  `nix flake check`
  `nix build .#nixosConfigurations.chromebook.config.system.build.toplevel`
  `nix build .#nixosConfigurations.vaio.config.system.build.toplevel`
- Lint / format (this repo follows nixfmt RFC style):
  `nix run nixpkgs#nixfmt -- --check flake.nix hosts/*/*.nix modules/nixos/*.nix modules/nixos/*/*.nix home/*.nix`
  (includes `modules/nixos/release.nix` for optional generation labels)
  (drop `--check` to reformat in place).

### Known gotchas (durable)

- `hosts/chromebook/hardware-configuration.nix` in this repo is the **delbin machine's generated
  config** (real `fileSystems` / boot modules), while `hosts/vaio/hardware-configuration.nix`
  is a generic `lib.mkDefault` placeholder. Before `nixos-rebuild switch` on real VAIO (or
  other) hardware, regenerate and replace the target `hosts/<host>/hardware-configuration.nix`
  (see `README.md`).
- Chromebook ALSA UCM merge in `modules/nixos/chromebook/audio.nix` copies from read-only
  `/nix/store` inputs with `cp -a --no-preserve=mode` so the tree stays writable.
- Graphify CLI (`graphify`) is optional for agents; install with
  `nix run nixpkgs#uv -- tool install graphifyy` then `export PATH="$HOME/.local/bin:$PATH"`.
  After code edits: `graphify update .`

### Branch workflow

Do all work on `main` (commits, PRs). Do not develop on `chromebook`. See
`.cursor/rules/branch-workflow.mdc`.

### Project rules (`.cursor/rules`)

Agents that do not auto-load `.cursor/rules/*.mdc` (such as Antigravity `agy` or
Codex) **must** check `.cursor/rules/` at the start of work and read all
`alwaysApply: true` rules (plus glob-scoped rules like `frontend-design.mdc`
when editing matching files):

- `avoid-premature-workarounds.mdc` — investigate root causes instead of switching to workarounds
- `backup-staging.mdc` — prefer declarative Nix config; stage only machine-specific state in `backup.nix` + `README.md`
- `branch-workflow.mdc` — develop and commit only on `main`, never `chromebook`
- `cheatsheet-expand.mdc` — also update `cheatsheetEntries` in `home/sway.nix` for reusable answers
- `commit-before-next-unit.mdc` — commit coherent finished units before starting the next unit
- `committing-changes-with-git.mdc` — git safety protocol, HEREDOC commit messages, push boundaries
- `communication-style.mdc` — concise, direct responses with minimal bolding
- `creating-pull-requests.mdc` — PR creation steps using `gh`
- `graphify-knowledge-graph.mdc` — hybrid use of `graphify-out/` and native search
- `investigate-before-conclude.mdc` — read logs, configs, and source before concluding
- `nix-eval-avoid-options.mdc` — avoid heavy `options` evals; use narrow `config.` or source reads
- `prefer-native-tools.mdc` — prefer native CLI / `nix run` over ad-hoc Python for simple tasks
