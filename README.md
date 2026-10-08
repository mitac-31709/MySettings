# MySettings — NixOS flake（mitac）

ホスト／ユーザー `mitac` 向けの Flakes + Home Manager 構成。ログインは **greetd + tuigreet** で、複数セッションを切り替え可能。

## ブランチ

| ブランチ | 用途 |
|----------|------|
| `main` | **作業・適用の既定**。汎用デスクトップ／ノート、および delbin Chromebook 向け設定を含む |
| `chromebook` | レガシー。新規作業には使わない |

## セッション（greetd + tuigreet）

起動後の tuigreet でセッションを選びます（`--remember-session` で前回選択を記憶）。一覧は `Name=` の番号順で **1. Sway** が先頭（ファイル名順ではない）。

| セッション | 内容 |
|------------|------|
| **Sway** | キーボード中心のタイル WM（第一環境）。waybar / mako / swayidle。ランチャーは **rofi**（Super+D）。キーボード配列は **jp** |
| **Plasma** | KDE Plasma 6（Wayland のみ。X11 セッションは置かない） |
| **GNOME** | GNOME Shell（Wayland）。greetd から選択 |
| **Xfce** | Xfce Session（Wayland / labwc）。greetd から選択 |
| **Caelestia-AW** | Hyprland（`start-hyprland`）+ Caelestia shell（動画壁紙対応フォーク） |
| **end4-pC** | Hyprland + Quickshell の end4-pC（Illogical Impulse の `hyprland.lua` / `hyprland-startup`） |

### 共通操作感（見た目は各環境のまま）

GUI セッションでは次を揃えています（テーマ・パネル・シェルの見た目は変更しません。**Super+Space** は Mozc 切替のまま）。

| 操作 | キー | 動作 |
|------|------|------|
| 検索 | **Super+R**（Sway は **Super+D**） | 各環境ネイティブの検索／ランチャー（Sway は rofi） |
| 端末 | **Ctrl+Alt+T** | Ghostty（Hyprland / Sway は Super+Return も可） |
| ロック | **Super+L** | 画面ロック（Plasma / GNOME / Xfce 既定系、Sway は swaylock、Hyprland は hyprlock） |
| クリップボード履歴 | **Super+V** | Sway / Hyprland は cliphist+rofi、Plasma は Klipper、GNOME は GPaste |
| タッチパッド | — | 自然スクロール off・タップクリック on・入力中もポインタ有効 |

| セッション | 検索／ランチャー |
|------------|------------------|
| **Sway** | **Super+D** → rofi（`-show drun`）。Super+F は fullscreen、Super+R は resize。キーボードは `xkb_layout=jp` |
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

### このマシン上の対応表（履歴・更新しない）

世代番号↔タグの対応表は **今後更新しない**。参照が必要なら `git tag -l 'gen/*'` や `nixos-rebuild list-generations` を使う。以下は過去スナップショット。

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

タグ一覧: `git tag -l 'gen/*'` または GitHub の Tags ページ。

## 前提条件

- Flakes が有効な NixOS マシン（この flake でも有効化します）
- 初回 rebuild の**前に**、`hosts/mitac/hardware-configuration.nix` を自分のマシンで生成したファイルに差し替えること
- 非フリーパッケージ（`affinity-v3`、`code-cursor`、`cursor-cli`、`jquake`、`parsec-bin`、`sendanywhere`、`steam`、`vivaldi`）は `flake.nix` で許可済み
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

`flake.lock` はリポジトリに含まれます。シェル関数 `rebuild`（先に `sudo` 認証、通常表示のままビルド中だけ `nom` ETA）とエイリアス `generations` は `home/shell.nix` で定義され、flake パスは `~/MySettings` 固定です（ホーム直下など、リポジトリ外からも実行可）。

## 同梱ソフトウェア

- **Neovim** — **LazyVim**（`home/nvim`）。**lazy.nvim** 自体は nixpkgs から同梱、それ以外のプラグインは lazy が管理
- **Cursor** — `code-cursor`（GUI）／`cursor-cli`（ターミナル Agent: `cursor-agent` / `agent`）
- **ChatGPT** — 公式 Linux デスクトップ（Codex 含む、`pkgs/chatgpt`、`.deb`）。アプリメニュー / `chatgpt`
- **DeepSeek Harness** — GUI（`deepseek-harness`、Chromium アプリ窓）。裏で `dsh web`（:3080）。初回は npm → `~/.local/share/deepseek-harness`。ランタイムは公式 Node（`pkgs/nodejs-official`；nixpkgs Node だと native addon が落ちる）
- **LibreChat** — GUI（`librechat`、Chromium アプリ窓 → :3081）。MongoDB 同梱。API 鍵は `/var/lib/librechat/credentials.env`
- **Parsec** — `parsec-bin`（Intel VA-API / `intel-media-driver` でハードウェアエンコード）
- **Steam** — `programs.steam.enable`
- **libvirt / QEMU/KVM** — `modules/nixos/virtualisation.nix`（`virt-manager` GUI、`virt-viewer`、Spice USB、`virtiofsd`）。初回は `virsh net-start default` / `net-autostart default`
- **Bottles** — Wine プレフィックス管理（一般の Windows アプリ用）。`home.packages`
- **Vivaldi** — `vivaldi`
- **Firefox** — `firefox`
- **Tor Browser** — `tor-browser`
- **JQuake** — `jquake` 1.8.4（日本のリアルタイム地震マップ）
- **ONLYOFFICE** — `onlyoffice-desktopeditors`（文書・表計算・プレゼン）
- **GIMP** — `gimp`（画像編集）
- **Affinity** — `affinity-v3`（Canva Affinity suite; Wine via [affinity-nix](https://github.com/mrshmllow/affinity-nix)。初回起動でライセンス／セットアップ。キャッシュ: `cache.forall.systems`）
- **LocalSend** — LAN ファイル転送（`programs.localsend`、ファイアウォール 53317）
- **RQuickShare** — Google Quick Share / Nearby Share の Linux クライアント（`rquickshare`）
- **Send Anywhere** — クロスプラットフォーム転送（`pkgs/sendanywhere`、upstream `.deb`）
- **wol-pc** — Wake-on-LAN クライアント（`~/Projects/wol-pc`）。依存: `sshpass` / `zenity`（`home.packages`）。設定は同ディレクトリの `config.env`
- **7-Zip** — `_7zip-zstd`（コマンド `7z` / `7zz`、Zstd ほか対応）+ GUI `peazip`（PeaZip）
- **tmux** — `runbtop <cmd>` で上部に実行出力（約 10 行）、下部に `btop`
- **Mozc** — Fcitx5 エンジン（日本語入力）
- **フォント** — JetBrainsMono Nerd Font（ターミナル／等幅の既定）
- **暗号化バックアップ** — `restic` + `rclone` で `/home` を Google Drive へ。鍵は Bitwarden（`rbw`）。詳細は下記。
- **マルチセッション** — greetd + tuigreet（Sway 第一 / Plasma / GNOME / Xfce / Caelestia-AW / end4-pC）
- **gui** — ディスプレイ無し時は `cage` で単一 GUI アプリを起動（`gui firefox` など）。引数なしは `apps` を起動
- **apps** — `fzf` アプリ一覧（`gui` 経由起動）。TTY やシェルから利用可。Sway の Super+D は dmenu 既定

- **Caelestia-AW** — Hyprland シェル（動画壁紙）。flake: `caelestia-shell-aw` / `caelestia-cli-aw`
- **end4-pC** — Quickshell 設定（`~/.config/quickshell/end4-pC`）+ Illogical Impulse の Hyprland 設定（`hyprland-startup` → `start-hyprland`）

## 日本語入力（Mozc）

Fcitx5 + Mozc を有効化しています。パネルの入力インジケータ、または **Super+Space**（Fcitx5 既定）で切り替えできます。
設定は **Fcitx5 設定**（`fcitx5-configtool`）から変更可能です。

## フォント

- システムの比例フォント既定: sans `Hiragino Kaku Gothic ProN` / serif `Hiragino Mincho ProN`（ローカル `~/Documents/hiragino-otf` → flake input `hiragino-fonts-src`）
- 等幅フォント既定: `JetBrainsMono Nerd Font`（日本語フォールバックにヒラギノ角ゴ ProN）
- Ghostty も JetBrainsMono（12pt）。Konsole を開いた場合のプロファイルも同フォント（`home/plasma.nix`）
- Nerd Font のアイコンが空白に見える場合: `fc-cache -rf` を実行し、ログアウトして再ログイン

## ターミナル

既定は **Ghostty**（`programs.ghostty`）。**Ctrl+Alt+T** で開きます（Plasma / GNOME / Xfce / Sway / Hyprland）。
`TERMINAL=ghostty` も Home Manager で設定しています。

## タッチパッド

ナチュラルスクロールはオフ（従来型: 指を上 → 内容が上）。キーボード入力中もタッチパッドは有効（`DisableWhileTyping=false`）。右クリックは **2本指タップ／2本指押し**（`TapToClick` + `ClickMethod=clickfinger`）。端を押すソフトボタン領域は使わない。delbin の Elan Touchpad 向けに `kcminputrc` で設定。

## クリップボード履歴

| セッション | 仕組み | 呼び出し |
|------------|--------|----------|
| **Sway / Hyprland** | `cliphist`（起動時に `wl-paste --watch`）+ `clipboard-history`（rofi → 選択で貼り付け） | **Super+V** |
| **Plasma** | Klipper（履歴保持を有効化） | **Super+V**（トレイからも可） |
| **GNOME** | GPaste（`programs.gpaste` + Shell 拡張） | **Super+V** |

## Encrypted /home backup

`modules/nixos/backup.nix` backs up the user's home **and selected system state** to
**Google Drive**, encrypted:

- **restic** — encrypted, deduplicated, snapshot backups of `/home/mitac` plus staged
  copies of NetworkManager Wi-Fi profiles, Bluetooth pairings, Cloudflare WARP
  state, and Tailscale node state.
- **rclone** — Google Drive backend (restic repo `rclone:gdrive:restic/mitac-home`).
- **Bitwarden (`rbw`)** — holds the restic encryption key. restic fetches it at
  runtime via `RESTIC_PASSWORD_COMMAND=rbw get restic-home`, so **no key material is
  written to disk or into the Nix store**. `rbw` itself is configured declaratively in
  `home/mitac.nix` (`programs.rbw`).

A daily `systemd` timer (`restic-backups-home.timer`) runs the backup and prunes old
snapshots (`--keep-daily 7 --keep-weekly 5 --keep-monthly 12`). While a graphical
session is logged in, **Sway waybar** shows live progress (`バックアップ N%`) via
`$XDG_RUNTIME_DIR/restic-home-status`, and mako notifications cover start / finish
(or failure).

### One-time setup (secrets stay out of git / the Nix store)

1. **Edit your identifiers** before rebuilding:
   - `home/programs.nix`: `programs.rbw.settings.email` → your Bitwarden email.
   - `modules/nixos/backup.nix` (optional): `repository`, `bitwardenItem`, `paths`.
2. **Rebuild**: `sudo nixos-rebuild switch --flake .#mitac`.
3. **Create your own Google Drive OAuth client** (required: rclone's shared client_id is being retired in 2026, and the shared quota is what makes restore crawl). See [Making your own client_id](https://rclone.org/drive/#making-your-own-client-id):
   1. [Google Cloud Console](https://console.cloud.google.com/) → new project (e.g. `rclone-mitac`).
   2. **APIs & Services → Library** → enable **Google Drive API**.
   3. **OAuth consent screen** → User type **External** → app name + your email.
   4. **Data Access** → add scopes:
      - `https://www.googleapis.com/auth/docs`
      - `https://www.googleapis.com/auth/drive`
      - `https://www.googleapis.com/auth/drive.metadata.readonly`
   5. **Audience** → **+ Add users** → add your Google account as a test user.
   6. **Clients → Create OAuth client** → Application type **Desktop app** → Create.
      Note the **Client ID** and **Client secret** (keep them private; never commit).
   7. **Audience → Publish app** (move out of Testing). Leaving it in Testing makes refresh tokens expire about weekly.
4. **Run the interactive setup** (rclone `gdrive` OAuth → Bitwarden key → first backup):
   ```bash
   restic-home-setup
   ```
   When rclone asks for `client_id` / `client_secret`, paste the values from step 3
   (do **not** leave them blank). Or configure / reconnect manually:
   ```bash
   # New remote
   rclone config
   # n → name: gdrive → storage: drive
   # client_id>   <your Client ID>
   # client_secret> <your Client secret>
   # scope> 1 (full drive) → browser OAuth

   # Existing remote that still uses the shared client_id:
   rclone config reconnect gdrive:
   # or: rclone config → e (edit) → gdrive → set client_id/secret → replace token (Y)
   ```
   Then Bitwarden + first backup:
   ```bash
   rbw login && rbw unlock
   rbw generate 40 restic-home   # password field = restic encryption key
   sudo systemctl start restic-backups-home.service
   journalctl -u restic-backups-home -f
   ```

### Restore / inspect

The module installs a `backup` wrapper preloaded with the repository, rclone config
and Bitwarden password command (and `restic-home-setup` for first-time setup):

```bash
restic-home-setup
backup snapshots
backup restore latest --target /tmp/restore
```

System state lands under `/tmp/restore/run/restic-backups-home/system/`:

```bash
# Wi-Fi
sudo cp /tmp/restore/run/restic-backups-home/system/nm-connections/* \
  /etc/NetworkManager/system-connections/
sudo chown root:root /etc/NetworkManager/system-connections/*
sudo chmod 600 /etc/NetworkManager/system-connections/*
sudo nmcli connection reload

# Bluetooth pairings
sudo cp -a /tmp/restore/run/restic-backups-home/system/bluetooth/. \
  /var/lib/bluetooth/
sudo chown -R root:root /var/lib/bluetooth
sudo systemctl restart bluetooth

# Cloudflare WARP device registration
sudo cp -a /tmp/restore/run/restic-backups-home/system/cloudflare-warp/. \
  /var/lib/cloudflare-warp/
sudo chown -R root:root /var/lib/cloudflare-warp
sudo systemctl restart cloudflare-warp 2>/dev/null || true

# Tailscale node state (login / keys)
sudo cp -a /tmp/restore/run/restic-backups-home/system/tailscale/. \
  /var/lib/tailscale/
sudo chown -R root:root /var/lib/tailscale
sudo systemctl restart tailscaled

# LibreChat credentials / uploads（会話 DB は MongoDB 側で別途）
sudo mkdir -p /var/lib/librechat
sudo cp -a /tmp/restore/run/restic-backups-home/system/librechat/. \
  /var/lib/librechat/
sudo chown -R librechat:librechat /var/lib/librechat
sudo systemctl restart librechat
```

If Drive restore is still rate-limited, copy the repo locally first, then restore from disk:

```bash
rclone copy gdrive:restic/mitac-home /var/tmp/restic-mitac-home \
  --fast-list --transfers 4 --checkers 8 --tpslimit 8 --drive-chunk-size 64M
restic restore latest \
  --repo /var/tmp/restic-mitac-home \
  --password-command 'rbw get restic-home' \
  --target /tmp/restore
```

### Notes

- The backup runs as user `mitac`; `rbw` must be **unlocked/reachable** for a run to
  succeed. Prefer keeping an unlocked `rbw-agent` in your graphical session. If the
  vault is locked when the timer fires, the password command imports your session
  D-Bus / Wayland (or X11) so `pinentry-qt` can prompt; with no session, unlock first
  (`rbw unlock`) and start the unit manually.
- Root-only trees (Wi-Fi, Bluetooth, Cloudflare WARP, Tailscale, LibreChat
  `/var/lib/librechat`) are staged by a root `ExecStartPre` into
  `/run/restic-backups-home/system/…`, then cleared on stop. MongoDB chat data is
  not staged.
  `/etc/shadow` (login password) and `~/MySettings` (git) are **not** backed up.
- Excluded regenerable bulk includes Steam client/runtime + game installs (saves in
  `userdata` / `compatdata` stay), Cursor agent-worker binaries and caches, Vivaldi
  caches / extensions / WebStorage, and Firefox `storage`.
- To back up **all** of `/home` (multiple users), change the service to run as `root`
  and configure root's `rclone`/`rbw` instead.
- The rclone OAuth token and Bitwarden login live under `~/.config` — never in this repo.

## Neovim 設定

[LazyVim](https://github.com/LazyVim/LazyVim) スターター構成（NixOS 向けに調整）。

| パス | 役割 |
|------|------|
| `home/nvim/init.lua` | `config.lazy` の読み込み |
| `home/nvim/lua/config/` | options / keymaps / autocmds / lazy セットアップ |
| `home/nvim/lua/plugins/` | 追加・上書き用のプラグイン仕様（`nix.lua` で Mason 無効化） |

- **lazy.nvim** 自体は Home Manager が `pkgs.vimPlugins.lazy-nvim` からインストール（git clone 不要）
- **LazyVim 本体と依存プラグイン**は初回起動時に lazy がクローン（要ネットワーク）
- `lazy-lock.json` は読み取り専用の `~/.config/nvim` ではなく `~/.local/state/nvim/lazy-lock.json`
- LSP / formatter 等は Mason ではなく `programs.neovim.extraPackages`（`home/programs.nix`）

## Chromebook — ASUS CX5500FE / delbin

| 項目 | 詳細 |
|------|------|
| ボード | `delbin`（`DELBIN_XHVI`） |
| プラットフォーム | `volteer`（Intel Tiger Lake） |
| GPU | Iris Xe（i3-1115G4）。`intel-media-driver` + `LIBVA_DRIVER_NAME=iHD`（Parsec 等の VA-API） |
| オーディオ | SOF + `sof-rt5682` / `max98373`（`alsa-ucm-conf-cros` + `sof-firmware`） |
| キーボード | [cros-keyboard-map](https://github.com/WeirdTreeThing/cros-keyboard-map) 相当の `keyd`（delbin physmap）。最上段は ChromeOS キー。**Search+最上段**で F1–F10。tuigreet セッション一覧は **Search+3つ目のキー（zoom/全画面）**。電源コード: 短押し=suspend / 長押し≈2.5s=poweroff / **電源+Back=強制ログアウト** / **電源+Refresh=再起動**（`chromebook-power-chords`）。USB/Bluetooth 外付け KB 接続中は内蔵 AT を `inhibited`（`chromebook-internal-kb-guard`） |
| Flip | タブレットモード向け libinput quirk `ModelTabletModeNoSuspend=1` |
| USB-C 電力 | `chromebook-typec-prefer-sink`: 空きポートは FORCE_SINK（壁充電器／モババッ受電）、スマホ(UFP)→ source、AC給電中の他ポート→ source。udev は partner 追加時のみ（typec CHANGE はループ防止で除外） |

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

外付け（USB/Bluetooth）キーボードがあるあいだ、内蔵の `AT Translated Set 2 keyboard` は `chromebook-internal-kb-guard` が `inhibited=1` にします（抜き差しで自動再評価）。

```bash
cat /sys/class/input/input0/inhibited   # 0=内蔵有効 / 1=無効
systemctl start chromebook-internal-kb-guard   # 手動再評価
```

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
home/sway.nix                     # Sway 第一環境（waybar/mako/swayidle・rofi・jp）
home/sessions/hyprland.nix        # Caelestia-AW / end4-pC（II hypr tree）
home/nvim/
```
