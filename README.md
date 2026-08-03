# MySettings — NixOS flake（mitac）

ホスト／ユーザー `mitac` 向けの Flakes + Home Manager 構成。ログインは **greetd + tuigreet** で、複数セッションを切り替え可能。

## ブランチ

| ブランチ | 用途 |
|----------|------|
| `main` | **作業・適用の既定**。汎用デスクトップ／ノート、および delbin Chromebook 向け設定を含む |
| `chromebook` | レガシー。新規作業には使わない |

## セッション（greetd + tuigreet）

起動後の tuigreet でセッションを選びます（`--remember-session` で前回選択を記憶）。**第一推奨は Sway**（一覧先頭）。

| セッション | 内容 |
|------------|------|
| **Sway** | キーボード中心のタイル WM（第一環境）。waybar / mako / swayidle。ランチャーは `apps`（fzf） |
| **Plasma** | KDE Plasma 6（Wayland のみ。X11 セッションは置かない） |
| **GNOME** | GNOME Shell（Wayland）。greetd から選択 |
| **Xfce** | Xfce Session（Wayland / labwc）。greetd から選択 |
| **Caelestia-AW** | Hyprland（`start-hyprland`）+ Caelestia shell（動画壁紙対応フォーク） |
| **end4-pC** | Hyprland + Quickshell の end4-pC（Illogical Impulse の `hyprland.lua` / `hyprland-startup`） |

### 共通操作感（見た目は各環境のまま）

GUI セッションでは次を揃えています（テーマ・パネル・シェルの見た目は変更しません。**Super+Space** は Mozc 切替のまま）。

| 操作 | キー | 動作 |
|------|------|------|
| 検索 | **Super+R**（Sway は **Super+F**） | 各環境ネイティブの検索／ランチャー |
| 端末 | **Ctrl+Alt+T** | Ghostty（Hyprland / Sway は Super+Return も可） |
| ロック | **Super+L** | 画面ロック（Plasma / GNOME / Xfce 既定系、Sway は swaylock、Hyprland は hyprlock） |
| タッチパッド | — | 自然スクロール off・タップクリック on・入力中もポインタ有効 |

| セッション | 検索／ランチャー |
|------------|------------------|
| **Sway** | **Super+F** → `apps`（fzf）。Super+D も `menu`（同じ）。Super+R は Sway 既定の resize。fullscreen は Super+Shift+F |
| **Plasma** | Super+R → KRunner（既定の Alt+Space 等も残す） |
| **GNOME** | Super+R → Overview の検索欄（Super 単体も従来どおり） |
| **Xfce** | Super+R → App Finder（`xfce4-appfinder`） |
| **Caelestia-AW** | Super+R → Caelestia launcher |
| **end4-pC** | Super+R → Quickshell 検索（Super タップも従来どおり） |

電源ボタン（全セッション共通・`chromebook-power-chords`）: 短押し=suspend / 長押し≈2.5s=poweroff / **電源+Back=強制ログアウト** / **電源+Refresh=再起動**。

共通（Sway / Hyprland 系）: Polkit / Fcitx5 / cliphist を起動時に起動。音量・輝度は PulseAudio / brightnessctl 経由。Sway は mako で通知、waybar でステータスバー。

Caelestia の動画壁紙は `~/Pictures/Wallpapers/Animated/` に配置（`.mp4` / `.webm` / `.mkv` / `.gif`）。

end4-pC は初回の matugen／壁紙自動適用をスキップして起動を安定化しています（外観はシェル既定色）。設定パネル（**Super+Escape**）から後で変更できます。

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
| 16 | （適用後にタグ予定） | `jquake` ラベル | Parsec VA-API + JQuake。`sudo nixos-rebuild switch` 後に `gen/16-jquake` を打つ |
| 17 | （適用後にタグ予定） | `sof-audio-stable` ラベル | SOF 音声安定化（WP suspend 無効・alsactl init）+ zram/oomd。`sudo nixos-rebuild switch` 後に `gen/17-sof-audio-stable` を打つ |
| 18 | （適用後にタグ予定） | `auto-cpufreq` ラベル | auto-cpufreq（PPD 無効）。`sudo nixos-rebuild switch` 後に `gen/18-auto-cpufreq` を打つ |
| 19 | （適用後にタグ予定） | `pulse-sof-fix` ラベル | 音声を PulseAudio へ（SOF Broken-pipe ループ回避）。`sudo nixos-rebuild switch` 後に `gen/19-pulse-sof-fix` を打つ |
| 20 | （適用後にタグ予定） | `pulse-hw-sink` ラベル | Pulse で sof スピーカーを hw:0,0 直結。`sudo nixos-rebuild switch` 後に `gen/20-pulse-hw-sink` を打つ |
| 21 | （適用後にタグ予定） | `xp-startup` ラベル | ログイン後に Windows XP 起動音。`sudo nixos-rebuild switch` 後に `gen/21-xp-startup` を打つ |
| 22 | （適用後にタグ予定） | `multi-session-greetd` ラベル | greetd+tuigreet・Console(cage)・Plasma・Caelestia-AW・end4-pC。`sudo nixos-rebuild switch` 後に `gen/22-multi-session-greetd` を打つ |
| 23 | （適用後にタグ予定） | `bottles` ラベル | Bottles（Windows アプリ用 Wine）。`sudo nixos-rebuild switch` 後に `gen/23-bottles` を打つ |
| 24 | （適用後にタグ予定） | `console-apps` ラベル | Console 用 `apps`（fzf アプリ一覧／起動）。`sudo nixos-rebuild switch` 後に `gen/24-console-apps` を打つ |
| 25 | （適用後にタグ予定） | `restic-notify` ラベル | restic バックアップ進捗を Plasma 通知で表示。`sudo nixos-rebuild switch` 後に `gen/25-restic-notify` を打つ |
| 26 | （適用後にタグ予定） | `session-stable` ラベル | 全セッション安定化（start-hyprland・Console TTY・end4 依存・Hyprland IM/polkit）。`sudo nixos-rebuild switch` 後に `gen/26-session-stable` を打つ |
| — | （適用後にタグ予定） | `power-back-logout` ラベル | power+Back 強制ログアウト（chord 検出）。`sudo nixos-rebuild switch` 後にタグを打つ |

タグ一覧: `git tag -l 'gen/*'` または GitHub の Tags ページ。

## 前提条件

- Flakes が有効な NixOS マシン（この flake でも有効化します）
- 初回 rebuild の**前に**、`hosts/mitac/hardware-configuration.nix` を自分のマシンで生成したファイルに差し替えること
- 非フリーパッケージ（`code-cursor`、`jquake`、`parsec-bin`、`steam`、`vivaldi`）は `flake.nix` で許可済み
- Chromebook: MrChromebox（または同等）の UEFI／WP 無効を想定。ファームウェアの書き込みはこのリポジトリの範囲外

## 適用手順

```bash
# NixOS マシン上で、このリポジトリから:
git checkout main

# ハードウェア設定を差し替え（必須）:
sudo nixos-generate-config --show-hardware-config > hosts/mitac/hardware-configuration.nix

# ビルドして切り替え:
sudo nixos-rebuild switch --flake .#mitac
# または（Home Manager 適用後）どのディレクトリからでも:
#   rebuild
# → sudo nixos-rebuild switch --flake ~/MySettings#mitac

# 必要なら:
passwd mitac
```

`flake.lock` はリポジトリに含まれます。シェルエイリアス `rebuild` / `generations` は `home/shell.nix` で定義され、flake パスは `~/MySettings` 固定です（ホーム直下など、リポジトリ外からも実行可）。

## 同梱ソフトウェア

- **Neovim** — 設定は `home/nvim`、プラグインは **lazy.nvim**（nixpkgs から同梱）
- **Cursor** — `code-cursor`
- **Parsec** — `parsec-bin`（Intel VA-API / `intel-media-driver` でハードウェアエンコード）
- **Steam** — `programs.steam.enable`
- **Bottles** — Wine プレフィックス管理（一般の Windows アプリ用）。`home.packages`
- **Vivaldi** — `vivaldi`
- **JQuake** — `jquake` 1.8.4（日本のリアルタイム地震マップ）
- **ONLYOFFICE** — `onlyoffice-desktopeditors`（文書・表計算・プレゼン）
- **tmux** — `runbtop <cmd>` で上部に実行出力（約 10 行）、下部に `btop`
- **Mozc** — Fcitx5 エンジン（日本語入力）
- **フォント** — JetBrainsMono Nerd Font（ターミナル／等幅の既定）
- **暗号化バックアップ** — `restic` + `rclone` で `/home` を Google Drive へ。鍵は Bitwarden（`rbw`）。詳細は下記。
- **マルチセッション** — greetd + tuigreet（Sway 第一 / Plasma / GNOME / Xfce / Caelestia-AW / end4-pC）
- **gui** — ディスプレイ無し時は `cage` で単一 GUI アプリを起動（`gui firefox` など）。引数なしは `apps` を起動
- **apps** — `fzf` アプリ一覧。Sway の Super+F（および Super+D）ランチャー。選択で `gui` 経由起動
- **Caelestia-AW** — Hyprland シェル（動画壁紙）。flake: `caelestia-shell-aw` / `caelestia-cli-aw`
- **end4-pC** — Quickshell 設定（`~/.config/quickshell/end4-pC`）+ Illogical Impulse の Hyprland 設定（`hyprland-startup` → `start-hyprland`）

## 日本語入力（Mozc）

Fcitx5 + Mozc を有効化しています。パネルの入力インジケータ、または **Super+Space**（Fcitx5 既定）で切り替えできます。
設定は **Fcitx5 設定**（`fcitx5-configtool`）から変更可能です。

## フォント

- システムの等幅フォント既定: `JetBrainsMono Nerd Font`（`fontconfig` + Plasma `kdeglobals` の `fixed`）
- Ghostty も同じフォント（12pt）。Konsole を開いた場合のプロファイルも同フォント（`home/plasma.nix`）
- Nerd Font のアイコンが空白に見える場合: `fc-cache -rf` を実行し、ログアウトして再ログイン

## ターミナル

既定は **Ghostty**（`programs.ghostty`）。**Ctrl+Alt+T** で開きます（Plasma / GNOME / Xfce / Sway / Hyprland）。
`TERMINAL=ghostty` も Home Manager で設定しています。

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
snapshots (`--keep-daily 7 --keep-weekly 5 --keep-monthly 12`). While a graphical
session is logged in, Plasma desktop notifications show start / progress / finish
(or failure) via `libnotify` (`restic-backups-home-progress.service`).

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
| キーボード | [cros-keyboard-map](https://github.com/WeirdTreeThing/cros-keyboard-map) 相当の `keyd`（delbin physmap）。最上段は ChromeOS キー。**Search+最上段**で F1–F10。tuigreet セッション一覧は **Search+3つ目のキー（zoom/全画面）**。電源コード: 短押し=suspend / 長押し≈2.5s=poweroff / **電源+Back=強制ログアウト** / **電源+Refresh=再起動**（`chromebook-power-chords`） |
| Flip | タブレットモード向け libinput quirk `ModelTabletModeNoSuspend=1` |

### オーディオ確認

```bash
aplay -l
# sof-rt5682 / SOF 関連のカード名のような表示を期待

pactl list short sinks
pactl info | grep 'Default Sink'
# speaker がデフォルトシンクであること
```

SOF（Tiger Lake）では PipeWire の ALSA バックエンドが `Broken pipe` になり、スピーカーが最後の音をループし続ける既知不具合があります（WeirdTreeThing/chromebook-linux-audio#2）。

対策:

- **音声は PulseAudio**（PipeWire はデスクトップ用のみ）。設定は `modules/nixos/chromebook/audio.nix`
- sof-rt5682 は UCM プロファイル探索に失敗するため、**`hw:0,0`（Speaker）を直接** `module-alsa-sink` でバインド
- 起動／レジューム時に `alsactl init` + `chromebook-speaker-levels apply`（max98373 Digital/Spk）
- 緊急停止: `audio-panic`（`chromebook-speaker-levels mute`）

```bash
pactl list short sinks   # speaker が見えること
speaker-test -c 2 -t wav -l 1
```

dmesg の `DMIC16kHz` IPC `-22` は NHLT に DMIC が無い場合の既知ノイズで、スピーカー不具合とは別件です。

### VA-API / Parsec 確認

```bash
vainfo
# iHD ドライバと H.264 の EncSlice / VLD が出ることを期待
```

Parsec を開き直してハードウェアエンコーダーが選べるか確認します。

### キーボード確認

最上段キーは Back / Forward / Refresh / Fullscreen / Brightness / Volume として動作するはずです（単なる F1–F10 ではありません）。

### モジュール

`modules/nixos/chromebook.nix` は `hosts/mitac/default.nix` から import され、`modules/nixos/chromebook/` 配下の audio / power / graphics / input を束ねます。

## 構成

```
flake.nix
hosts/mitac/
modules/nixos/common.nix          # locale、ユーザー、mozc、フォント
modules/nixos/desktop.nix         # plasma + gnome + xfce + sway + greetd + console-gui + hyprland + 共有 XKB/印刷
modules/nixos/plasma.nix          # Plasma DE のみ
modules/nixos/gnome.nix
modules/nixos/xfce.nix            # Xfce Wayland（labwc）
modules/nixos/sway.nix            # Sway（第一環境・waybar/mako 等）
modules/nixos/greetd.nix          # tuigreet + セッション選別（Sway 先頭）
modules/nixos/greetd/sessions.nix # Caelestia / end4 ラッパー
modules/nixos/hyprland.nix        # portals / Hyprland 共通パッケージ / QML
modules/nixos/console-gui.nix     # gui / apps（Sway ランチャー等）
modules/nixos/chromebook.nix      # delbin 集約（./chromebook/*）
modules/nixos/chromebook/         # audio / power / graphics / input
modules/nixos/backup.nix          # encrypted /home → Google Drive (restic/rclone/rbw)
modules/nixos/release.nix         # system.nixos.tags（世代ラベルのスラッグ）
home/mitac.nix                    # HM エントリ（identity + imports）
home/shell.nix                    # bash エイリアス / runbtop
home/programs.nix                 # git / rbw / neovim / 共通パッケージ
home/plasma.nix                   # Plasma 設定・Konsole・起動音
home/gnome.nix                    # GNOME ショートカット／タッチパッド
home/xfce.nix                     # Xfce ショートカット（見た目は既定）
home/sway.nix                     # Sway 第一環境（waybar/mako/swayidle・apps）
home/sessions/hyprland.nix        # Caelestia-AW / end4-pC（II hypr tree）
home/nvim/
```
