# MySettings — NixOS flake（mitac）

ホスト／ユーザー `mitac` 向けの Flakes + Home Manager 構成（GNOME）。

## ブランチ

| ブランチ | 用途 |
|----------|------|
| `main` | **作業・適用の既定**。汎用デスクトップ／ノート、および delbin Chromebook 向け設定を含む |
| `chromebook` | レガシー。新規作業には使わない |

## 前提条件

- Flakes が有効な NixOS マシン（この flake でも有効化します）
- 初回 rebuild の**前に**、`hosts/mitac/hardware-configuration.nix` を自分のマシンで生成したファイルに差し替えること
- 非フリーパッケージ（`code-cursor`、`parsec-bin`、`steam`、`vivaldi`）は `flake.nix` で許可済み
- Chromebook: MrChromebox（または同等）の UEFI／WP 無効を想定。ファームウェアの書き込みはこのリポジトリの範囲外

## 適用手順

```bash
# NixOS マシン上で、このリポジトリから:
git checkout main

# ハードウェア設定を差し替え（必須）:
sudo nixos-generate-config --show-hardware-config > hosts/mitac/hardware-configuration.nix

# ビルドして切り替え:
sudo nixos-rebuild switch --flake .#mitac

# 必要なら:
passwd mitac
```

`flake.lock` は、Nix があるマシンで初回の評価／rebuild 時に作成されます。

## 同梱ソフトウェア

- **Neovim** — 設定は `home/nvim`、プラグインは **lazy.nvim**（nixpkgs から同梱）
- **Cursor** — `code-cursor`
- **Parsec** — `parsec-bin`
- **Steam** — `programs.steam.enable`
- **Vivaldi** — `vivaldi`
- **Mozc** — IBus エンジン（日本語入力）
- **フォント** — JetBrainsMono Nerd Font（ターミナル／等幅の既定）
- **暗号化バックアップ** — `restic` + `rclone` で `/home` を Google Drive へ。鍵は Bitwarden（`rbw`）。詳細は下記。

## 日本語入力（Mozc）

IBus + Mozc を有効化し、GNOME の入力ソースに **Japanese (Mozc)** を dconf で追加しています。
パネルの入力インジケータ、または **Super+Space** で切り替えできます。
ショートカットは **設定 → キーボード → キーボードショートカット → 入力** で変更可能です。

## フォント

- システムの等幅フォント既定: `JetBrainsMono Nerd Font`
- GNOME Console も dconf 経由で同じフォントを使用
- Nerd Font のアイコンが空白に見える場合: `fc-cache -rf` を実行し、ログアウトして再ログイン

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

## Neovim 設定

| パス | 役割 |
|------|------|
| `home/nvim/init.lua` | オプション + lazy のブートストラップ |
| `home/nvim/lua/plugins/` | プラグイン仕様 |

プラグインは `lua/plugins/` 以下に追加します。lazy.nvim 自体は Home Manager が `pkgs.vimPlugins.lazy-nvim` からインストールします（git clone によるブートストラップは不要）。

## Chromebook — ASUS CX5500FE / delbin

| 項目 | 詳細 |
|------|------|
| ボード | `delbin`（`DELBIN_XHVI`） |
| プラットフォーム | `volteer`（Intel Tiger Lake） |
| オーディオ | SOF + `sof-rt5682` / `max98373`（`alsa-ucm-conf-cros` + `sof-firmware`） |
| キーボード | `keyd` が最上段を ChromeOS 風メディアキーに割り当て |
| Flip | タブレットモード向け libinput quirk `ModelTabletModeNoSuspend=1` |

### オーディオ確認

```bash
aplay -l
# sof-rt5682 / SOF 関連のカード名のような表示を期待
```

起動後に音が出ない場合は、`modules/nixos/chromebook.nix` 内のコメントにある任意の `alsactl init` や modprobe の調整を参照してください。

### キーボード確認

最上段キーは Back / Forward / Refresh / Fullscreen / Brightness / Volume として動作するはずです（単なる F1–F10 ではありません）。

### モジュール

`modules/nixos/chromebook.nix` は `hosts/mitac/default.nix` から import されます。

## 構成

```
flake.nix
hosts/mitac/
modules/nixos/common.nix      # locale、ユーザー、mozc、フォント
modules/nixos/gnome.nix
modules/nixos/chromebook.nix  # delbin 専用
modules/nixos/backup.nix      # encrypted /home → Google Drive (restic/rclone/rbw)
home/mitac.nix
home/nvim/
```
