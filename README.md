# MySettings — NixOS flake (mitac)

Flakes + Home Manager configuration for host/user `mitac` with GNOME.

## Branches

| Branch | Use |
|--------|-----|
| `main` | Generic desktop / laptop |
| `chromebook` | **ASUS CX5500FE (delbin / DELBIN_XHVI)** — keyd, SOF audio, Flip quirks |

## Prerequisites

- NixOS machine with flakes enabled (this flake also enables them)
- Replace `hosts/mitac/hardware-configuration.nix` with your machine’s generated file **before** the first rebuild
- Unfree packages (`code-cursor`, `parsec-bin`) are allowed in `flake.nix`
- Chromebook: MrChromebox (or equivalent) UEFI / WP disabled is assumed; firmware flashing is out of scope for this repo

## Apply

```bash
# On the NixOS machine, from this repository:
git checkout chromebook   # CX5500FE — or: git checkout main

# Replace hardware config (required):
sudo nixos-generate-config --show-hardware-config > hosts/mitac/hardware-configuration.nix

# Build and switch:
sudo nixos-rebuild switch --flake .#mitac

# If needed:
passwd mitac
```

`flake.lock` is created on the first evaluation/rebuild on a machine that has Nix.

## Included software

- **Neovim** — config in `home/nvim`, plugins via **lazy.nvim** (bundled from nixpkgs)
- **Cursor** — `code-cursor`
- **Parsec** — `parsec-bin`
- **Mozc** — IBus engine (Japanese input)
- **Font** — JetBrainsMono Nerd Font (terminal / monospace default)
- **Encrypted backup** — `restic` + `rclone` back up `/home` to Google Drive; encryption key in Bitwarden (`rbw`). See below.

## Japanese input (Mozc)

After login, open **Settings → Keyboard → Input Sources**, add **Japanese (Mozc)**, and set a switch shortcut if desired.

## Fonts

- System monospace default: `JetBrainsMono Nerd Font`
- GNOME Console uses the same font via dconf
- If Nerd Font icons look blank: run `fc-cache -rf`, then log out and back in

## Encrypted /home backup

`modules/nixos/backup.nix` backs up the user's home to **Google Drive**, encrypted:

- **restic** — encrypted, deduplicated, snapshot backups (`/home/mitac`).
- **rclone** — Google Drive backend (restic repo `rclone:gdrive:restic/mitac-home`).
- **Bitwarden (`rbw`)** — holds the restic encryption key. restic fetches it at
  runtime via `RESTIC_PASSWORD_COMMAND=rbw get restic-home`, so **no key material is
  written to disk or into the Nix store**. `rbw` itself is configured declaratively in
  `home/mitac.nix` (`programs.rbw`).

A daily `systemd` timer (`restic-backups-home.timer`) runs the backup and prunes old
snapshots (`--keep-daily 7 --keep-weekly 5 --keep-monthly 12`).

### One-time setup (secrets stay out of git / the Nix store)

1. **Edit your identifiers** before rebuilding:
   - `home/mitac.nix`: `programs.rbw.settings.email` → your Bitwarden email.
   - `modules/nixos/backup.nix` (optional): `repository`, `bitwardenItem`, `paths`.
2. **Rebuild**: `sudo nixos-rebuild switch --flake .#mitac`.
3. **Configure the Google Drive rclone remote named `gdrive`** (OAuth, interactive):
   ```bash
   rclone config
   # n(ew) → name: gdrive → storage: drive → follow the browser OAuth
   # (headless? use: rclone authorize "drive" on a machine with a browser)
   ```
   This writes `~/.config/rclone/rclone.conf` (contains the OAuth token; keep it private).
4. **Store the encryption key in Bitwarden** as an item named `restic-home` whose
   password is a strong passphrase:
   ```bash
   rbw login          # uses the email from home/mitac.nix
   rbw unlock         # GNOME pinentry prompts for your master password
   # Create the item (or add it in the Bitwarden app); its password IS the restic key:
   rbw generate 40 restic-home
   rbw get restic-home   # should print the key
   ```
5. **First backup** (also creates the repo, `initialize = true`):
   ```bash
   sudo systemctl start restic-backups-home.service
   journalctl -u restic-backups-home -f
   ```

### Restore / inspect

The module installs a `restic-home` wrapper preloaded with the repository, rclone config
and Bitwarden password command:

```bash
restic-home snapshots
restic-home restore latest --target /tmp/restore
```

### Notes

- The backup runs as user `mitac`; `rbw` must be **unlocked/reachable** for a run to
  succeed. For unattended timer runs keep an unlocked `rbw-agent` in your session, or
  trigger backups manually after `rbw unlock`.
- To back up **all** of `/home` (multiple users), change the service to run as `root`
  and configure root's `rclone`/`rbw` instead.
- The rclone OAuth token and Bitwarden login live under `~/.config` — never in this repo.

## Neovim config

| Path | Role |
|------|------|
| `home/nvim/init.lua` | Options + lazy bootstrap |
| `home/nvim/lua/plugins/` | Plugin specs |

Add plugins under `lua/plugins/`. lazy.nvim itself is installed by Home Manager from `pkgs.vimPlugins.lazy-nvim` (no git clone bootstrap).

## Chromebook (this branch) — ASUS CX5500FE / delbin

| Item | Detail |
|------|--------|
| Board | `delbin` (`DELBIN_XHVI`) |
| Platform | `volteer` (Intel Tiger Lake) |
| Audio | SOF + `sof-rt5682` / `max98373` via `alsa-ucm-conf-cros` + `sof-firmware` |
| Keyboard | `keyd` maps top-row to ChromeOS-style media keys |
| Flip | libinput quirk `ModelTabletModeNoSuspend=1` for tablet mode |

### Audio check

```bash
aplay -l
# Expect something like sof-rt5682 / SOF-related card names
```

If there is no sound after boot, see comments in `modules/nixos/chromebook.nix` for optional `alsactl init` and modprobe tweaks.

### Keyboard check

Top-row keys should act as Back / Forward / Refresh / Fullscreen / Brightness / Volume (not plain F1–F10).

### Module

`modules/nixos/chromebook.nix` is imported only on this branch from `hosts/mitac/default.nix`.

## Layout

```
flake.nix
hosts/mitac/
modules/nixos/common.nix      # locale, user, mozc, fonts
modules/nixos/gnome.nix
modules/nixos/chromebook.nix  # delbin only (this branch)
modules/nixos/backup.nix      # encrypted /home → Google Drive (restic/rclone/rbw)
home/mitac.nix
home/nvim/
```
