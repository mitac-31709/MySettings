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
| **Sway** | キーボード中心のタイル WM（第一環境）。waybar / mako / swayidle。ランチャーは **rofi**（Super+D / Alt+Space）。キーボード配列は **jp** |
| **Plasma** | KDE Plasma 6（Wayland のみ。X11 セッションは置かない）。既定アプリは Sway スタックに寄せている |

### 共通操作感（見た目は各シェルのまま）

GUI セッションでは次を揃えています（テーマ・パネルの見た目は変更しません。**Super+Space** は Meltype / Mozc 切替のまま）。

| 操作 | キー | 動作 |
|------|------|------|
| 検索／ランチャー | **Super+D**（Sway）/ **Super+R**・**Alt+Space**（両環境） | **rofi**（Plasma の Alt+F2 だけ KRunner 残し） |
| 端末 | **Ctrl+Alt+T**（Sway は Super+Return も可） | **Ghostty** |
| ファイルマネージャ | **Super+E** | **Yazi**（Ghostty 内） |
| ロック | **Super+L** | Plasma 既定ロック / Sway は swaylock |
| クリップボード履歴 | **Super+V** | **cliphist** + rofi（両環境） |
| スクショ | **Print** / **Super+Shift+S** | **grim**（全画面）/ grim+**slurp**（範囲）→ クリップボード |
| タッチパッド | — | 自然スクロール off・タップクリック on・入力中もポインタ有効 |

Plasma では Konsole / Dolphin / Kate / Ark / Spectacle / Okular / Gwenview / Elisa などを `environment.plasma6.excludePackages` で外し、上記スタックを既定にしています。

電源ボタン（全セッション共通・`chromebook-power-chords`）: 短押し=suspend / 長押し≈2.5s=poweroff / **電源+Back=強制ログアウト** / **電源+Refresh=再起動**。

共通: Polkit / Fcitx5 / cliphist（systemd user）を起動時に起動。音量・輝度は PulseAudio / brightnessctl 経由。Sway は mako で通知、waybar でステータスバー。

## 世代とコミットの対応

NixOS の世代番号はマシン固有です。コミットとの対応はビルド時の **`system.nixos.tags` / `system.configurationRevision`** で追います（`gen/NN-*` の Git タグ運用は廃止済み。既存タグは履歴として残っていてよい）。

| 場所 | 何がわかるか |
|------|----------------|
| ブートメニュー / `nixos-rebuild list-generations` | `system.nixos.label`（`tags` + NixOS バージョン）。例: `rofi-cheatsheet-26.11....` |
| `nixos-version --json` の `configurationRevision` | その世代をビルドした git コミット（フル SHA） |

任意でブートメニュー用スラッグを変えるときは `modules/nixos/release.nix` の `system.nixos.tags` を更新してから rebuild してください。

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
- **Parsec** — `parsec-bin`（Intel VA-API / `intel-media-driver` でハードウェアエンコード）
- **Steam** — `programs.steam.enable`
- **libvirt / QEMU/KVM** — `modules/nixos/virtualisation.nix`（`virt-manager` GUI、`virt-viewer`、Spice USB、`virtiofsd`）。初回は `virsh net-start default` / `net-autostart default`
- **Bottles** — Wine プレフィックス管理（一般の Windows アプリ用）。`home.packages`
- **Vivaldi** — `vivaldi`
- **Firefox** — `firefox`
- **Tor Browser** — `tor-browser`
- **JQuake** — `JQuake` / `jquake`（nixpkgs 1.8.5 + `pkgs/jquake` ラッパー。Sway では `_JAVA_AWT_WM_NONREPARENTING` 必須）
- **ONLYOFFICE** — `onlyoffice-desktopeditors`（文書・表計算・プレゼン）
- **GIMP** — `gimp`（画像編集）
- **Affinity** — `affinity-v3`（Canva Affinity suite; Wine via [affinity-nix](https://github.com/mrshmllow/affinity-nix)。初回起動でライセンス／セットアップ。キャッシュ: `cache.forall.systems`）
- **LocalSend** — LAN ファイル転送（`programs.localsend`、ファイアウォール 53317）
- **RQuickShare** — Google Quick Share / Nearby Share の Linux クライアント（`rquickshare`）
- **Send Anywhere** — クロスプラットフォーム転送（`pkgs/sendanywhere`、upstream `.deb`）
- **wol-pc** — Wake-on-LAN クライアント（`~/Projects/wol-pc`）。依存: `sshpass` / `zenity`（`home.packages`）。設定は同ディレクトリの `config.env`
- **7-Zip** — `_7zip-zstd`（コマンド `7z` / `7zz`、Zstd ほか対応）+ GUI `peazip`（PeaZip）
- **tmux** — `runbtop <cmd>` で上部に実行出力（約 10 行）、下部に `btop`
- **Meltype** — Fcitx5 エンジン（日本語／英語の自動打ち分け。Linux プレビュー）。フォールバックに Mozc
- **フォント** — JetBrainsMono Nerd Font（ターミナル／等幅の既定）
- **暗号化バックアップ** — `restic` + `rclone` で `/home` を Google Drive へ。鍵は Bitwarden（`rbw`）。詳細は下記。
- **マルチセッション** — greetd + tuigreet（Sway 第一 / Plasma）
- **gui** — ディスプレイ無し時は `cage` で単一 GUI アプリを起動（`gui firefox` など）。引数なしは `apps` を起動
- **apps** — `fzf` アプリ一覧（`gui` 経由起動）。TTY やシェルから利用可。Sway の Super+D は rofi

## 日本語入力（Meltype / Fcitx5）

[Meltype](https://github.com/yksr-melt/Meltype)（Linux プレビュー）を **Fcitx5** アドオンとして入れています（Sway / Plasma の Wayland セッション向け）。半角/全角なしでローマ字の日本語と英語を打ち分けます。Mozc はフォールバックとして同じグループに残しています。

- 切替: パネルの入力インジケータ、または **Super+Space**（Fcitx5）
- Meltype 内の英数 ⇔ 日本語: **半角/全角**
- 学習・設定: `~/.local/share/Meltype`
- 詳細設定: **Fcitx5 設定**（`fcitx5-configtool`）
- プロファイル: Home Manager が `/etc/xdg/fcitx5/profile` を `~/.config/fcitx5/profile` に同期（ユーザー側の古い Mozc のみ設定で Meltype が消えないように）

## フォント

- システムの比例フォント既定: sans `Hiragino Kaku Gothic ProN` / serif `Hiragino Mincho ProN`（ローカル `~/Documents/hiragino-otf` → flake input `hiragino-fonts-src`）
- 等幅フォント既定: `JetBrainsMono Nerd Font`（日本語フォールバックにヒラギノ角ゴ ProN）
- Ghostty も JetBrainsMono（12pt）
- Nerd Font のアイコンが空白に見える場合: `fc-cache -rf` を実行し、ログアウトして再ログイン

## ターミナル

既定は **Ghostty**（`programs.ghostty`）。**Ctrl+Alt+T** で開きます（Sway / Plasma）。
`TERMINAL=ghostty` も Home Manager で設定しています。

## タッチパッド

ナチュラルスクロールはオフ（従来型: 指を上 → 内容が上）。キーボード入力中もタッチパッドは有効（`DisableWhileTyping=false`）。右クリックは **2本指タップ／2本指押し**（`TapToClick` + `ClickMethod=clickfinger`）。端を押すソフトボタン領域は使わない。delbin の Elan Touchpad 向けに `kcminputrc` で設定。

## クリップボード履歴

両セッションとも `cliphist`（systemd user の `wl-paste --watch`）+ `clipboard-history`（rofi → 選択で貼り付け）。呼び出しは **Super+V**。

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
   7. **Audience → Publish app** (move out of Testing). **Required for unattended
      backups** — Testing issues refresh tokens that die about every **7 days**
      (`invalid_grant` / `rclone config reconnect gdrive:`). Publishing does **not**
      require Google verification for personal single-user use (you'll see an
      "unverified app" warning once at reconnect; that is fine).
      If **Publish** is greyed out, Google wants Branding on a **domain you own**
      (Search Console verified). `github.io` is often rejected — use:
      - App name (exact): `restic Home Backup`
      - Home: https://restic-oauth.mitac.f5.si/
      - Privacy: https://restic-oauth.mitac.f5.si/privacy.html
      - Authorized domain: `mitac.f5.si` (verify in
        [Search Console](https://search.google.com/search-console) as a Domain
        property with the same Google account as the GCP project)
      After saving, wait up to 24h if ownership was just verified, then request
      branding re-check with **「問題は修正した」** (the findings are real —
      do not pick “issues are incorrect”). Then Audience → Publish.
      See [rclone: Making your own client_id](https://rclone.org/drive/#making-your-own-client-id).
4. **Run the interactive setup** (rclone `gdrive` OAuth → Bitwarden key → first backup):
   ```bash
   backup setup          # same as restic-home-setup
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

   # Token dead / weekly invalid_grant (after Publishing the OAuth app):
   backup reconnect
   backup about          # smoke check

   # Existing remote that still uses the shared client_id:
   backup reconnect
   # or: rclone config → e (edit) → gdrive → set client_id/secret → replace token (Y)
   ```
   Then Bitwarden + first backup:
   ```bash
   rbw login && backup unlock-key
   rbw generate 40 restic-home   # password field = restic encryption key
   backup run
   backup log
   ```

### Restore / inspect

The module installs a `backup` CLI for setup, the systemd unit, rclone checks, and
restic (repo / Bitwarden password command preloaded). `restic-home-setup` remains as
an alias of `backup setup`:

```bash
backup                 # usage
backup setup
backup run && backup log
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
  (`backup unlock-key`) and start with `backup run`.
- Root-only trees (Wi-Fi, Bluetooth, Cloudflare WARP, Tailscale) are staged by a
  root `ExecStartPre` into `/run/restic-backups-home/system/…`, then cleared on
  stop. `/etc/shadow` (login password) and `~/MySettings` (git) are **not**
  backed up.
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
| キーボード | [cros-keyboard-map](https://github.com/WeirdTreeThing/cros-keyboard-map) 相当の `keyd`（delbin physmap）。最上段は ChromeOS キー。**Search+最上段**で F1–F10。tuigreet セッション一覧は **Search+3つ目のキー（zoom/全画面）**。**Ctrl+Alt+Del**（内蔵は **Ctrl+Alt+Backspace**）で手動 OOM killer。電源コード: 短押し=suspend / 長押し≈2.5s=poweroff / **電源+Back=強制ログアウト** / **電源+Refresh=再起動**（`chromebook-power-chords`）。USB/Bluetooth 外付け KB 接続中は内蔵 AT を `inhibited`（`chromebook-internal-kb-guard`） |
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
modules/nixos/desktop.nix         # plasma + sway + greetd + console-gui + portals + 共有 XKB/印刷
modules/nixos/plasma.nix          # Plasma DE + 既定アプリ除外
modules/nixos/sway.nix            # Sway（第一環境・waybar/mako 等）
modules/nixos/greetd.nix          # tuigreet + セッション選別（Sway / Plasma）
modules/nixos/console-gui.nix     # gui / apps（Sway ランチャー等）
modules/nixos/chromebook.nix      # delbin 集約（./chromebook/*）
modules/nixos/chromebook/         # audio / power / graphics / input
modules/nixos/backup.nix          # encrypted /home → Google Drive (restic/rclone/rbw)
modules/nixos/release.nix         # system.nixos.tags（世代ラベルのスラッグ）
home/mitac.nix                    # HM エントリ（identity + imports）
home/shell.nix                    # bash エイリアス / runbtop
home/programs.nix                 # git / rbw / neovim / 共通パッケージ
home/plasma.nix                   # Plasma 既定アプリ／ショートカット・起動音
home/clipboard.nix                # cliphist + clipboard-history（両セッション）
home/sway.nix                     # Sway 第一環境（waybar/mako/swayidle・rofi・jp）
home/nvim/
```
