# MySettings — NixOS flake（mitac）

ホスト／ユーザー `mitac` 向けの Flakes + Home Manager 構成（KDE Plasma）。

## ブランチ

| ブランチ | 用途 |
|----------|------|
| `main` | **作業・適用の既定**。汎用デスクトップ／ノート、および delbin Chromebook 向け設定を含む |
| `chromebook` | レガシー。新規作業には使わない |

## 世代と Git タグ

NixOS の世代番号はマシン固有です。コミットとの対応は **Git タグ**（`gen/NN-<slug>`）と、ビルド時の **`system.nixos.tags` / `system.configurationRevision`** で追います。

| 場所 | 何がわかるか |
|------|----------------|
| ブートメニュー / `nixos-rebuild list-generations` | `system.nixos.label`（`tags` + NixOS バージョン）。例: `plasma-gnome-prefs-26.11....` |
| `nixos-version --json` の `configurationRevision` | その世代をビルドした git コミット（フル SHA） |
| GitHub タグ `gen/NN-<slug>` | 「世代 NN 相当」のマイルストーンコミットと注釈（特徴の説明） |

スラッグの定義は `modules/nixos/release.nix` です。特徴が変わったらスラッグを更新してから rebuild してください。

### 新しいマイルストーンを残す手順

```bash
# 1. 機能変更をコミットしたあと、release.nix の tags を更新してコミット
# 2. 適用（ラベル付きの新世代ができる）
sudo nixos-rebuild switch --flake .#mitac

# 3. いまの世代番号を確認してタグを打つ
nixos-rebuild list-generations   # または generations
git tag -a "gen/NN-<slug>" -m "世代 NN: 短い特徴の説明"
git push origin "gen/NN-<slug>"
```

### このマシン上の対応表（2026-07-28 時点）

ラベル導入前の世代は `Configuration Revision` が Unknown です。近いコミットをタグで示します。

| 世代 | Git タグ | コミット | 特徴 |
|------|----------|----------|------|
| 1–2 | （タグなし） | インストーラ初期 | ホスト名 `nixos`、GNOME、NixOS 26.05 |
| 3 | `gen/03-flake-gnome` | `c268ec9` | 初回 flake 適用（ホスト `mitac`）、GNOME、delbin HW |
| 4 | `gen/04-alsa-boot` | `1728296` | Chromebook ALSA UCM コピー修正、初回起動まわり |
| 5 | `gen/05-steam` | `e59b411` | Steam / Vivaldi、flake.lock |
| 6 | `gen/06-backup` | `fab332b` | restic + rclone + rbw による暗号化 /home バックアップ（Console ショートカット含む） |
| 7 | `gen/07-btop` | `34300df` | `btop` |
| 8 | `gen/08-hm-backup` | `11cf80a` | HM 衝突ファイルの `.backup`、git user 設定 |
| 9 | （タグなし） | ≈ `11cf80a` | 8 相当の再適用（この間にユニークなコミットなし） |
| 10 | `gen/10-gpaste` | `6389334` | GPaste（GNOME クリップボード） |
| 11 | `gen/11-plasma` | `3d85378` | GNOME → KDE Plasma 6（この世代は Bluetooth 無効） |
| 12 | `gen/12-bluetooth` | `f2a271c` | Bluetooth + A2DP（PipeWire） |
| 13 | `gen/13-rbw-eu` | `879c43c` | rbw を Bitwarden EU エンドポイントへ |
| 14 | `gen/14-plasma-numlock` | `f72575e` | 初のラベル付き世代。NumLock 既定オン（ログイン＋Plasma）。`configurationRevision` 付き |
| 15 | `gen/15-plasma-gnome-prefs` | `32034aa` | 旧 GNOME dconf 相当を Plasma へ（タッチパッド／Konsole フォント／Ctrl+Alt+T） |
| 16 | （適用後にタグ予定） | `parsec-vaapi` ラベル | 2本指右クリック + Intel VA-API（Parsec HW エンコード）。`sudo nixos-rebuild switch` 後に `gen/16-parsec-vaapi` を打つ |

タグ一覧: `git tag -l 'gen/*'` または GitHub の Tags ページ。

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
- **Parsec** — `parsec-bin`（Intel VA-API / `intel-media-driver` でハードウェアエンコード）
- **Steam** — `programs.steam.enable`
- **Vivaldi** — `vivaldi`
- **ONLYOFFICE** — `onlyoffice-desktopeditors`（文書・表計算・プレゼン）
- **tmux** — `runbtop <cmd>` で上部に実行出力（約 10 行）、下部に `btop`
- **Mozc** — Fcitx5 エンジン（日本語入力）
- **フォント** — JetBrainsMono Nerd Font（ターミナル／等幅の既定）
- **暗号化バックアップ** — `restic` + `rclone` で `/home` を Google Drive へ。鍵は Bitwarden（`rbw`）。詳細は下記。

## 日本語入力（Mozc）

Fcitx5 + Mozc を有効化しています。パネルの入力インジケータ、または **Super+Space**（Fcitx5 既定）で切り替えできます。
設定は **Fcitx5 設定**（`fcitx5-configtool`）から変更可能です。

## フォント

- システムの等幅フォント既定: `JetBrainsMono Nerd Font`（`fontconfig` + Plasma `kdeglobals` の `fixed`）
- Konsole 既定プロファイルも同じフォント（12pt）を使用（`home/mitac.nix`）
- Nerd Font のアイコンが空白に見える場合: `fc-cache -rf` を実行し、ログアウトして再ログイン

## ターミナル

**Ctrl+Alt+T** で Konsole を開きます（旧 GNOME Console ショートカット相当）。

## タッチパッド

ナチュラルスクロールはオフ（従来型: 指を上 → 内容が上）。キーボード入力中もタッチパッドは有効（`DisableWhileTyping=false`）。右クリックは **2本指タップ／2本指押し**（`TapToClick` + `ClickMethod=clickfinger`）。端を押すソフトボタン領域は使わない。delbin の Elan Touchpad 向けに `kcminputrc` で設定。

## クリップボード履歴

Plasma 標準の **クリップボード**（システムトレイ、または **Meta+V**）を使います。

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
   rbw unlock         # pinentry prompts for your master password
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
| GPU | Iris Xe（i3-1115G4）。`intel-media-driver` + `LIBVA_DRIVER_NAME=iHD`（Parsec 等の VA-API） |
| オーディオ | SOF + `sof-rt5682` / `max98373`（`alsa-ucm-conf-cros` + `sof-firmware`） |
| キーボード | `keyd` が最上段を ChromeOS 風メディアキーに割り当て |
| Flip | タブレットモード向け libinput quirk `ModelTabletModeNoSuspend=1` |

### オーディオ確認

```bash
aplay -l
# sof-rt5682 / SOF 関連のカード名のような表示を期待
```

起動後に音が出ない場合は、`modules/nixos/chromebook.nix` 内のコメントにある任意の `alsactl init` や modprobe の調整を参照してください。

### VA-API / Parsec 確認

```bash
vainfo
# iHD ドライバと H.264 の EncSlice / VLD が出ることを期待
```

Parsec を開き直してハードウェアエンコーダーが選べるか確認します。

### キーボード確認

最上段キーは Back / Forward / Refresh / Fullscreen / Brightness / Volume として動作するはずです（単なる F1–F10 ではありません）。

### モジュール

`modules/nixos/chromebook.nix` は `hosts/mitac/default.nix` から import されます。

## 構成

```
flake.nix
hosts/mitac/
modules/nixos/common.nix      # locale、ユーザー、mozc、フォント
modules/nixos/plasma.nix
modules/nixos/chromebook.nix  # delbin 専用
modules/nixos/backup.nix      # encrypted /home → Google Drive (restic/rclone/rbw)
modules/nixos/release.nix     # system.nixos.tags（世代ラベルのスラッグ）
home/mitac.nix
home/nvim/
```
