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

## Japanese input (Mozc)

After login, open **Settings → Keyboard → Input Sources**, add **Japanese (Mozc)**, and set a switch shortcut if desired.

## Fonts

- System monospace default: `JetBrainsMono Nerd Font`
- GNOME Console uses the same font via dconf
- If Nerd Font icons look blank: run `fc-cache -rf`, then log out and back in

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
home/mitac.nix
home/nvim/
```
