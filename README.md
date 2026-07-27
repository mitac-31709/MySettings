# MySettings — NixOS flake (mitac)

Flakes + Home Manager configuration for host/user `mitac` with GNOME.

## Branches

| Branch | Use |
|--------|-----|
| `main` (or `master`) | Generic desktop / laptop |
| `chromebook` | ASUS CX5500FE (delbin) extras — keyd, SOF audio, etc. |

## Prerequisites

- NixOS machine with flakes enabled (this flake also enables them)
- Replace `hosts/mitac/hardware-configuration.nix` with your machine’s generated file **before** the first rebuild
- Unfree packages (`code-cursor`, `parsec-bin`) are allowed in `flake.nix`

## Apply

```bash
# On the NixOS machine, from this repository:
git checkout main   # or: git checkout chromebook

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

IBus + Mozc is enabled, and **Japanese (Mozc)** is added to GNOME input sources via dconf.
Switch with the panel indicator or **Super+Space**.
Shortcuts can be changed in **Settings → Keyboard → Keyboard Shortcuts → Typing**.

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

## Layout

```
flake.nix
hosts/mitac/
modules/nixos/common.nix   # locale, user, mozc, fonts
modules/nixos/gnome.nix
home/mitac.nix
home/nvim/
```
