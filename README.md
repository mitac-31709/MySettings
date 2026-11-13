# MySettings — NixOS flake（mitac）

ホスト／ユーザー `mitac` 向けの Flakes + Home Manager 構成。ログインは **greetd + tuigreet**、デスクトップは **Sway のみ**。**VAIO（Intel 第8世代以降）** と **Chromebook（ASUS CX5500FE / delbin）** の両対応です。

## ブランチ

| ブランチ | 用途 |
|----------|------|
| `main` | **作業・適用の既定**。VAIO（`.#vaio`）および delbin Chromebook（`.#chromebook`、レガシー別名 `.#mitac`）向け設定を含む |
| `chromebook` | レガシー。新規作業には使わない |

## セッション（greetd + tuigreet）

起動後の tuigreet でログインします（`--remember` / `--remember-session`、未記憶時は `--cmd sway`）。提供セッションは **Sway** のみ。

| セッション | 内容 |
|------------|------|
| **Sway** | キーボード中心のタイル WM。waybar / mako / swayidle。ランチャーは **rofi**（Super+D / Alt+Space）。キーボード配列は **jp** |

### 操作感

**Super+Space** は Fcitx5 の IME 有効/無効（グループは Meltype のみ）。

| 操作 | キー | 動作 |
|------|------|------|
| 検索／ランチャー | **Super+D** / **Alt+Space** | **rofi** |
| 端末 | **Ctrl+Alt+T** / **Super+Return** | **Ghostty** |
| ファイルマネージャ | **Super+E** | **Yazi**（Ghostty 内） |
| ロック | **Super+L** | swaylock |
| クリップボード履歴 | **Super+V** | **cliphist** + rofi |
| スクショ | **Print** / **Super+Shift+S** | **grim**（全画面）/ grim+**slurp**（範囲）→ クリップボード |
| タッチパッド | — | 自然スクロール off・タップクリック on・入力中もポインタ有効 |

電源ボタン（`power-chords`）: 短押し=suspend / 長押し≈2.5s=poweroff / **電源+F1（Chromebook は 電源+Back）=強制ログアウト** / **電源+F2（Chromebook は 電源+Refresh）=再起動**。

Polkit / Fcitx5 / cliphist（systemd user）を起動時に起動。音量は PulseAudio（Chromebook）または PipeWire / `pipewire-pulse`（VAIO）経由で `pactl` 操作、輝度は `brightnessctl` 経由。通知は mako、ステータスバーは waybar。

## 世代とコミットの対応

NixOS の世代番号はマシン固有です。コミットとの対応はビルド時の **`system.nixos.tags` / `system.configurationRevision`** で追います（`gen/NN-*` の Git タグ運用は廃止済み。既存タグは履歴として残っていてよい）。

| 場所 | 何がわかるか |
|------|----------------|
| ブートメニュー / `nixos-rebuild list-generations` | `system.nixos.label`（`tags` + NixOS バージョン）。例: `rofi-cheatsheet-26.11....` |
| `nixos-version --json` の `configurationRevision` | その世代をビルドした git コミット（フル SHA） |

任意でブートメニュー用スラッグを変えるときは `modules/nixos/release.nix` の `system.nixos.tags` を更新してから rebuild してください。

## 前提条件

- Flakes が有効な NixOS マシン（この flake でも有効化します）
- 初回 rebuild の**前に**、対象ホストの `hosts/<target>/hardware-configuration.nix` を実機で生成したファイルに差し替えること（`hosts/vaio/hardware-configuration.nix` は汎用テンプレート、`hosts/chromebook/hardware-configuration.nix` は delbin 実機設定）
- 非フリーパッケージ（`code-cursor`、`cursor-cli`、`jquake`、`parsec-bin`、`steam`、`vivaldi`）は `flake.nix` で許可済み。`affinity-v3` は未導入（戻し方は下記）
- Chromebook: MrChromebox（または同等）の UEFI／WP 無効を想定。ファームウェアの書き込みはこのリポジトリの範囲外

## USB からの新規インストールと初回設定

新しい PC や空の SSD へ NixOS Live USB から導入する手順です。この flake は `systemd-boot`（UEFI 専用、`modules/nixos/common.nix`）と `zramSwap`（RAM 100% / `zstd`、`modules/nixos/laptop/power.nix`）を使うため、**UEFI ブート有効（セキュアブート無効）**・GPT（ESP + root、swap パーティション不要）を前提とします。

> **初期設定（Live USB・TTY）は英語設定で行う**: 初期状態の NixOS コンソール TTY には日本語フォント（CJK グリフ）が含まれず、日本語ロケールでは文字化けします（`modules/nixos/greetd.nix` も同理由で ASCII 時刻表示）。そのため、Live USB 起動時・Calamares インストーラの言語／ロケールは **English**（`en_US.UTF-8`）のまま進め、キーボード配列のみ日本語（**Japanese** / `jp106`）に設定してください。初期設定で使うスクリプト（`./scripts/restore-on-nixos.sh`・`backup setup`・`backup --help`）も TTY 上で読めるよう英語表示にしてあります。flake 適用・再起動後は `modules/nixos/common.nix` により自動的に `ja_JP.UTF-8` と日本語 Sway 環境へ切り替わります。

### 0. USB メディアの作成と起動

1. [NixOS ダウンロードページ](https://nixos.org/download/) から **Graphical ISO**（GUI インストーラ付き・推奨）または **Minimal ISO**（CLI のみ）を取得し、USB メモリへ書き込む。
2. 対象機の UEFI 設定で Secure Boot を無効にし、USB から **UEFI モード**で起動する（Chromebook は事前に MrChromebox 等の UEFI ファームウェアを導入しておく）。

### 1. NixOS の導入（2 パターン）

#### パターン A: Graphical ISO の GUI インストーラで最小導入してから適用（推奨）

既存バックアップを `./scripts/restore-on-nixos.sh` で復元する場合（`mitac` ユーザーで実機 NixOS 上から実行する設計）は、この手順が最も安全です。

1. Live 環境で Wi-Fi 等へ接続し、**Install NixOS**（Calamares）を起動する。
2. インストーラで以下を設定してインストールする：
   - 言語／ロケール（Welcome / Location）: **English**（American English / `en_US.UTF-8`）を選択（TTY での文字化け防止のため初期設定は英語。タイムゾーンは Tokyo を選んでよい。flake 適用後に `ja_JP.UTF-8` へ切り替わります）
   - キーボード（Keyboard）: **Japanese** を選択
   - ユーザー名: **`mitac`**（`lib/machine.nix` の `/home/mitac/MySettings`・各種設定と一致させる）＋ 任意のパスワード
   - デスクトップ環境: **No desktop**（後の flake 適用で Sway 環境一式が入るため最小構成でよい）
   - パーティション: ディスク消去（UEFI / GPT）を選択。swap は **No swap**（`zramSwap` を使用）でも問題ない
3. 完了後に USB を抜いて再起動し、`mitac` でログインする。
4. 作業コピーを `~/MySettings` へ取得する（初回は最小環境のため `nix-shell` で `git` を一時利用）：
   ```bash
   nix-shell -p git --run \
     'git clone -b main https://github.com/mitac31709/MySettings.git ~/MySettings'
   cd ~/MySettings
   ```
5. **（既存バックアップからデータを戻す場合）** OS ビルドの前に「[OS ビルド前に実機へ復元](#os-ビルド前に実機へ復元)」の手順で `./scripts/restore-on-nixos.sh` を実行し（出力は TTY 向けに英語表示）、必要なホームデータ・システム状態・ヒラギノフォント（`/home/mitac/Documents/hiragino-otf/`）を配置しておく（スクリプトは `/var/tmp/restore-mitac-YYYYMMDD-HHMMSS/` へ展開するため `~/MySettings` は上書きされません）。
6. 実機の `hardware-configuration.nix` を生成し、flake を適用する（対象は `vaio` または `chromebook`）：
   ```bash
   # VAIO の場合（Chromebook は hosts/chromebook/hardware-configuration.nix と .#chromebook）
   sudo nixos-generate-config --show-hardware-config > hosts/vaio/hardware-configuration.nix

   # 適用（~/Documents/hiragino-otf が既にある場合は `--impure` を追加）
   sudo NIX_CONFIG='experimental-features = nix-command flakes' \
     nixos-rebuild switch --flake .#vaio
   ```
7. 完了後、カーネル／bootvine／greetd／Sway セッションをクリーンに反映するため `sudo reboot` する。

#### パターン B: Minimal ISO（CLI）から `nixos-install --flake` で直接導入

GUI インストーラを経由せず、USB から直接この flake の環境を書き込む手順です（Live 環境上には `/home/mitac/Documents/hiragino-otf` が無いため、初回は Noto CJK でビルドされます）。

1. ロケールは ISO 既定の英語（`en_US.UTF-8`）のまま（TTY 文字化け防止）、必要なら日本語配列とネットワークを設定する：
   ```bash
   loadkeys jp106
   nmtui                        # Wi-Fi / 有線ネットワーク接続
   ```
2. `lsblk` で対象ディスクを確認し、GPT パーティション作成・フォーマット・マウントを行う（**対象ディスクの全データが消去されます**。例: NVMe の `/dev/nvme0n1` — eMMC なら `/dev/mmcblk0`、SATA なら `/dev/sda` に読み替え）：
   ```bash
   sudo parted /dev/nvme0n1 -- mklabel gpt
   sudo parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1GiB
   sudo parted /dev/nvme0n1 -- set 1 esp on
   sudo parted /dev/nvme0n1 -- mkpart root ext4 1GiB 100%

   sudo mkfs.fat -F 32 -n boot /dev/nvme0n1p1
   sudo mkfs.ext4 -L nixos /dev/nvme0n1p2

   sudo mount /dev/nvme0n1p2 /mnt
   sudo mkdir -p /mnt/boot
   sudo mount -o umask=0077 /dev/nvme0n1p1 /mnt/boot
   ```
3. ハードウェア設定生成と作業用リポジトリの用意を行う（`/mnt/home/mitac` は `nixos-install` 時に正しい所有者で作成させるため、ここでは `/tmp/MySettings` へ clone します）：
   ```bash
   sudo nixos-generate-config --root /mnt

   nix-shell -p git --run '
     sudo git clone -b main https://github.com/mitac31709/MySettings.git /tmp/MySettings
   '

   # 生成した実機構成を対象ホストへコピー（Chromebook の場合は chromebook に読み替え）
   sudo cp /mnt/etc/nixos/hardware-configuration.nix \
     /tmp/MySettings/hosts/vaio/hardware-configuration.nix
   ```
4. flake でインストールする（対象は `#vaio` または `#chromebook`）：
   ```bash
   sudo NIX_CONFIG='experimental-features = nix-command flakes' \
     nixos-install --flake /tmp/MySettings#vaio
   ```
   プロンプトに従って `root` パスワードを設定する。
5. **【必須】再起動前に作業コピーの配置・`mitac` のパスワード設定・所有者変更を行う**（`modules/nixos/common.nix` に初期パスワードが無いため、未設定だと `tuigreet` でログインできません）：
   ```bash
   sudo cp -a /tmp/MySettings /mnt/home/mitac/MySettings
   sudo nixos-enter --root /mnt
   passwd mitac
   chown -R mitac:users /home/mitac/MySettings
   exit
   ```
6. アンマウントして USB を抜き、再起動する：
   ```bash
   sudo umount -R /mnt
   sudo reboot
   ```

### 2. 初回ログイン後の設定チェックリスト

再起動後の `tuigreet` でユーザー `mitac` を選んでログインすると **Sway** が起動します（端末: **Ctrl+Alt+T** / **Super+Return**、IME トグル: **Super+Space**、英数⇔日本語: **半角/全角**、ランチャー: **Super+D** / **Alt+Space**）。秘密情報・認証・機体固有ファイルはリポジトリに含まれないため、実機で一度だけ次を設定します。

1. **GitHub 認証（`gh`）**:
   `gh auth login` を実行する（`programs.gh` の `gitCredentialHelper` が有効なため、以降の `~/MySettings` での `git push` / `pull` にも使われます）。
2. **VPN（Tailscale / Cloudflare WARP）**（※ バックアップから `/var/lib/{tailscale,cloudflare-warp}` を復元しなかった場合）：
   - Tailscale: `sudo tailscale up --operator=mitac`（自宅外でのみ必要な場合は `ts-home-routes off` のまま維持）
   - Cloudflare WARP: `warp-cli registration new` → `warp-cli connect`
3. **暗号化バックアップの復元または新規設定**:
   - **別機体の既存バックアップから復元する場合**: 「[OS ビルド前に実機へ復元](#os-ビルド前に実機へ復元)」および「復元・確認（適用済みの環境）」を参照し、`rclone config`（`gdrive`）と `rbw` ログインを行って復元する（**新しい鍵を作らないこと**）。
   - **新規でバックアップを初期構築する場合**: 「`/home の暗号化バックアップ` → `初回セットアップ`」に従い、GCP OAuth クライアント作成 → `backup setup` → `rbw login && backup unlock-key` → `rbw generate 40 restic-home` → `backup run` を実行する。
4. **ヒラギノフォント（任意）**:
   `/home/mitac/Documents/hiragino-otf/` に OTF ファイルを配置し、`rebuild` を実行する（ディレクトリが存在すると `rebuild` が自動で `--impure` を付けて同梱します）。
5. **Vivaldi × ChatGPT 拡張（利用する場合）**:
   Vivaldi で Web Store 版を入れた後、`vivaldi-chatgpt-extension-patch` が `~/.local/share/vivaldi-chatgpt-extension` を生成するため、`vivaldi://extensions` で Store 版を無効化し、Developer mode → Load unpacked で同ディレクトリを読み込む。
6. **その他の任意設定と実機確認**:
   - **リモートビルダー**（`modules/nixos/remote-builder.nix`）: 利用する場合は `/home/mitac/.ssh/id_wsl_builder`（パスフレーズなし）を配置し、公開鍵を `galleria-mitac` 側へ登録する（未配置でもタイムアウト後にローカルビルドへフォールバック。待ち時間を省くなら `sudo nixos-rebuild switch --flake .#vaio --option builders ""` を実行）。
   - **dsh-TUI**: `npm i -g @deepseek-ai/dsh @deepseek-harness-tui/dsh-tui`
   - **ハードウェア確認**: 下記「VAIO オーディオ確認」「Chromebook オーディオ確認」「VA-API / Parsec 確認」を実行する。

### Chromebook を btrfs 透過圧縮でクリーン再インストール

Chromebook（delbin）を既存の `ext4` から `btrfs`（`compress=zstd:1`）へ安全に切り替える手順です。`modules/nixos/common.nix` は `fileSystems` 内の `btrfs` を自動検出し、有効化された環境でのみ `compsize` と月次の `services.btrfs.autoScrub` を組み込みます（現在の `hosts/chromebook/hardware-configuration.nix` は `ext4` のままなので、実機を入れ替える前の既存環境にも影響しません）。

#### 事前準備（移行前の現在の Chromebook 上）

1. **最新のバックアップを取得・確認する**：
   ```bash
   backup run
   backup log
   backup snapshots
   ```
2. `~/MySettings` に未プッシュの変更があれば確認して GitHub へプッシュする（`git status`）。
3. 再インストール後にすぐ復元できるよう、**別の USB メモリ等へ秘密ファイルを退避**し、Bitwarden のログイン情報も手元に控えておく（Git には絶対に含めない）：
   - `~/.config/rclone/rclone.conf`（OAuth `client_id` / `client_secret`・トークン入り。これを戻せば `rclone config` のやり直しを省けます）
   - 利用している場合は `~/.ssh/id_wsl_builder`

#### Live USB からの `btrfs` 導入（CLI 手順）

Calamares（Graphical ISO）で `btrfs` を選ぶと初回導入時は `compress=zstd:1` が付かないため、**USB のターミナルから下記手順で最初からマウントオプション付きで導入する**のが確実です（最初の `nixos-install` 時点から `/nix/store` も圧縮されます）。

1. Live USB を UEFI 起動し、ロケールは ISO 既定の英語（`en_US.UTF-8`）のまま（TTY 文字化け防止）、日本語配列・ネットワークを設定する：
   ```bash
   loadkeys jp106
   nmtui
   ```
2. `lsblk` で内蔵ストレージを確認し、GPT パーティション作成・フォーマットを行う（delbin は個体により NVMe の `/dev/nvme0n1` または eMMC の `/dev/mmcblk0`。以下は `nvme0n1` の例、eMMC なら `/dev/mmcblk0p1`・`p2` に読み替え。**既存 ext4 データは消去されます**）：
   ```bash
   sudo parted /dev/nvme0n1 -- mklabel gpt
   sudo parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1GiB
   sudo parted /dev/nvme0n1 -- set 1 esp on
   sudo parted /dev/nvme0n1 -- mkpart root btrfs 1GiB 100%

   sudo mkfs.fat -F 32 -n boot /dev/nvme0n1p1
   # 既存の ext4 署名を上書きするため -f を指定
   sudo mkfs.btrfs -f -L nixos /dev/nvme0n1p2
   ```
3. サブボリューム（`@` / `@home` / `@nix` / `@log`）を作成し、`compress=zstd:1,noatime` でマウントする（同一プール上のため各領域の空き容量を柔軟に共有できます）：
   ```bash
   sudo mount /dev/nvme0n1p2 /mnt
   sudo btrfs subvolume create /mnt/@
   sudo btrfs subvolume create /mnt/@home
   sudo btrfs subvolume create /mnt/@nix
   sudo btrfs subvolume create /mnt/@log
   sudo umount /mnt

   sudo mount -o subvol=@,compress=zstd:1,noatime /dev/nvme0n1p2 /mnt
   sudo mkdir -p /mnt/{home,nix,var/log,boot}
   sudo mount -o subvol=@home,compress=zstd:1,noatime /dev/nvme0n1p2 /mnt/home
   sudo mount -o subvol=@nix,compress=zstd:1,noatime /dev/nvme0n1p2 /mnt/nix
   sudo mount -o subvol=@log,compress=zstd:1,noatime /dev/nvme0n1p2 /mnt/var/log
   sudo mount -o umask=0077 /dev/nvme0n1p1 /mnt/boot
   ```
4. `hardware-configuration.nix` を生成して `#chromebook` をインストールする：
   ```bash
   sudo nixos-generate-config --root /mnt

   nix-shell -p git --run '
     sudo git clone -b main https://github.com/mitac31709/MySettings.git /tmp/MySettings
   '

   sudo cp /mnt/etc/nixos/hardware-configuration.nix \
     /tmp/MySettings/hosts/chromebook/hardware-configuration.nix

   sudo NIX_CONFIG='experimental-features = nix-command flakes' \
     nixos-install --flake /tmp/MySettings#chromebook
   ```
5. `MySettings` の配置・`mitac` パスワード設定・所有者変更を行ってから再起動する：
   ```bash
   sudo cp -a /tmp/MySettings /mnt/home/mitac/MySettings
   sudo nixos-enter --root /mnt
   passwd mitac
   chown -R mitac:users /home/mitac/MySettings
   exit

   sudo umount -R /mnt
   sudo reboot
   ```

#### 再起動後の復元と圧縮確認

1. `tuigreet` で `mitac` にログインする（Sway 起動）。
2. 退避した `~/.config/rclone/rclone.conf` を戻す（`chmod 600 ~/.config/rclone/rclone.conf`）か「[OS ビルド前に実機へ復元](#os-ビルド前に実機へ復元)」の `rclone config` 手順を実行し、続けて `rbw login && rbw unlock` を実行する（期限切れ時は `rclone config reconnect gdrive:`）。
3. `./scripts/restore-on-nixos.sh`（TTY 互換のため英語出力）を実行し、`/var/tmp/restore-mitac-YYYYMMDD-HHMMSS/` へ復元された `/home/mitac`・`/home/mitac/Documents/hiragino-otf/`・システム状態（Wi-Fi / Bluetooth / WARP / Tailscale）を実機へ反映する（確認後に `/var/tmp/restore-mitac-YYYYMMDD-HHMMSS/` を削除）。
4. ヒラギノ等を戻した場合は `rebuild` を実行し、圧縮率と scrub タイマーを確認する：
   ```bash
   sudo compsize / /nix/store /home
   systemctl list-timers 'btrfs-scrub*'
   ```
5. 最後に `gh auth login` を行い、`~/MySettings/hosts/chromebook/hardware-configuration.nix`（新しい Btrfs UUID / サブボリューム構成）をコミット・プッシュする。

## 適用手順

新しく USB から環境を構築する場合は、先に「[USB からの新規インストールと初回設定](#usb-からの新規インストールと初回設定)」を参照してください。既存バックアップからデータを戻す場合は、先に「[OS ビルド前に実機へ復元](#os-ビルド前に実機へ復元)」を実行してください。

```bash
# NixOS マシン上で、このリポジトリから:
git checkout main

# 1) VAIO（Intel 第8世代以降）の場合 — 初回はハードウェア設定の差し替えが必須:
sudo nixos-generate-config --show-hardware-config > hosts/vaio/hardware-configuration.nix
sudo nixos-rebuild switch --flake .#vaio

# 2) Chromebook（ASUS CX5500FE / delbin）の場合（別個体では再生成）:
# sudo nixos-generate-config --show-hardware-config > hosts/chromebook/hardware-configuration.nix
sudo nixos-rebuild switch --flake .#chromebook
# ※ 後方互換エイリアス `.#mitac` も `.#chromebook` を指します

# Home Manager 適用後は、どのディレクトリからでも:
#   rebuild          # 現在のホストターゲット（vaio / chromebook）を再ビルド
#   rebuild vaio     # 引数でターゲット明示も可能

# 必要なら:
passwd mitac
```

`flake.lock` はリポジトリに含まれます。シェル関数 `rebuild`（既定ターゲットは各ホストの `flakeTarget`／未指定時のフォールバックは `lib/machine.nix` の `flakeHost`、引数で `.#vaio` / `.#chromebook` の切り替え可。先に `sudo` 認証、通常表示のままビルド中だけ `nom` ETA）とエイリアス `generations` は `home/shell.nix` で定義されます。flake の作業コピーは `lib/machine.nix` の `repoPath`（既定 `/home/mitac/MySettings`）だけです。Home Manager の `mitac.repoPath` / `mitac.flakeHost` で上書きできます。`rebuild` / `flake-update` はそのパスの `flake.nix` を使います。スクリプト本体は Nix ストアのコマンドで、チェックアウトの `scripts/` を直接実行しません。

## flake の更新

`nixpkgs` と `nixpkgs-cursor` はどちらも `nixos-unstable` を追います。`nix flake update` を引数なしで走らせると両方が同じコミットになり、Cursor だけ新しい nixpkgs を使う意味がなくなります。

`flake-update` は UniClipboard / ChatGPT / Grok Bot の .deb URL を `flake.nix` に書いたあと、lock に載っている入力のうち `nixpkgs-cursor` 以外を `nix flake update` します。システムの nixpkgs は動き、Cursor のピンは残ります。

Cursor（`code-cursor` / `cursor-cli`）だけ新しい nixpkgs にするときは、作業コピーで次のどちらかです。

```bash
flake-update-cursor
nix flake update nixpkgs-cursor
```

どちらも `nixpkgs-cursor` だけを取り直します。差分を見てコミットしてから `rebuild` します。

## 同梱ソフトウェア

- **Neovim** — **LazyVim**（`home/nvim`）。コアプラグインと treesitter のパーサは nixpkgs から同梱し、起動時に git clone しない
- **Cursor** — `code-cursor`（GUI）／`cursor-cli`（ターミナル Agent: `cursor-agent` / `agent`）
- **Zed** — `zed-editor`（起動: `zeditor`、アプリメニュー: Zed）
- **OpenCode** — ターミナル AI コーディングエージェント（`opencode`、`pkgs/opencode` で V2 をピン留め。nixpkgs の 1.x は使わない）
- **Claude Code** — Anthropic のターミナルエージェント（`claude`、nixpkgs `claude-code`）
- **Antigravity** — Google のターミナルエージェント（`agy` / `antigravity`、`pkgs/antigravity` で CLI バイナリをピン留め）
- **dsh-TUI** — DeepSeek Harness の TUI（`dsh-tui` / `dst`）。Node のグローバル npm（`~/.npm-global`、`.npmrc` の `prefix`）へ `npm i -g @deepseek-ai/dsh @deepseek-harness-tui/dsh-tui`。初回起動でプロファイルを初期化（`pnpm` 必須）。モデル利用は `DEEPSEEK_API_KEY` または `/auth`
- **ChatGPT** — 公式 Linux デスクトップ（Codex 含む、`pkgs/chatgpt`、`.deb`）。アプリメニュー / `chatgpt`。起動時に Vivaldi 等向け Native Messaging（`com.openai.codexextension`）を入れ、ブラウザ拡張の Browser Use を有効化する
- **Vivaldi × ChatGPT 拡張** — Vivaldi は `chrome.sidePanel.setOptions` を無視するため、Web Store 版は side panel が真っ白になる（VB-120826）。`vivaldi-chatgpt-extension-patch` が `~/.local/share/vivaldi-chatgpt-extension` に `default_path=codex-work-sidepanel.html` の unpacked 版を作る。初回だけ `vivaldi://extensions` で Store 版を無効化し、Developer mode → Load unpacked でそのディレクトリを読み込む
- **Node.js / pnpm** — `node` / `npm` / `pnpm`（グローバル npm は `~/.npm-global`）
- **Parsec** — `parsec-bin`（Intel VA-API / `intel-media-driver` でハードウェアエンコード）。ホテル等で `-6023/-11010` になるときは Tailscale 経由（下記）
- **Steam** — `programs.steam.enable`
- **Bottles** — Wine プレフィックス管理（一般の Windows アプリ用）。`home.packages`
- **Vivaldi** — `vivaldi`
- **Firefox** — `firefox`
- **Tor Browser** — `tor-browser`
- **JQuake** — `JQuake` / `jquake`（1.8.4 + `pkgs/jquake` ラッパー。Sway AWT 修正・更新ダイアログ無効化）。ログイン時に `jquake.service` で常駐（Sway では offscreen `stalonetray` に吸い込み、waybar には出さない）。警報時は全画面＋`swaylock` 解除（`home/jquake.nix`）
- **ONLYOFFICE** — `onlyoffice-desktopeditors`（文書・表計算・プレゼン）
- **Affinity** — 未導入（`affinity-v3` なし。flake 入力も overlay も外してある）。戻すときは次の 3 箇所です。
  1. `flake.nix` の `inputs` に `affinity-nix.url = "github:mrshmllow/affinity-nix";` を足し、`nixpkgs.overlays` の先頭に `inputs.affinity-nix.overlays.default` を戻す
  2. `home/programs.nix` の `home.packages` に `affinity-v3` を足す
  3. `modules/nixos/common.nix` の `nix.settings` に `cache.forall.systems` の substituter と公開鍵を戻す（コメントに残してある）
  Wine ビルドはキャッシュが外れると数時間かかることがあります。RTC が NTP より遅れていると、このキャッシュの証明書エラーで他の取得まで止まります
- **LocalSend** — LAN ファイル転送（`programs.localsend`、ファイアウォール 53317）
- **RQuickShare** — Google Quick Share / Nearby Share の Linux クライアント（`rquickshare`）
- **wol-pc** — Wake-on-LAN クライアント（`~/Projects/wol-pc`）。依存: `sshpass` / `zenity`（`home.packages`）。設定は同ディレクトリの `config.env`。ソースはこのリポジトリの外なので、ここではパッケージ化していない。TODO: ソースをこの flake に置く（`pkgs/wol-pc` にスクリプトを追加するか、公開リポジトリなら `fetchFromGitHub`）→ `callPackage` で `home.packages` に足す。`config.env` のホスト名やパスワードは秘密なのでストアに入れず、今どおりリポジトリ外のファイルのまま読む
- **7-Zip** — `_7zip-zstd`（コマンド `7z` / `7zz`、Zstd ほか対応）+ GUI `peazip`（PeaZip）
- **tmux** — `runbtop <cmd>` で上部に実行出力（約 10 行）、下部に `btop`
- **Meltype** — Fcitx5 エンジン（日本語／英語の自動打ち分け。Linux プレビュー。IME は Meltype のみ）
- **フォント** — JetBrainsMono Nerd Font（ターミナル／等幅の既定）
- **暗号化バックアップ** — `restic` + `rclone` で `/home` を Google Drive へ。鍵は Bitwarden（`rbw`）。詳細は下記。
- **デスクトップ** — greetd + tuigreet（Sway のみ）
- **bootvine** — 起動コンソールに systemd ジョブの依存ツリーを表示（[bootvine](https://codeberg.org/wvhulle/bootvine)、`services.bootvine.enable`）。反映には `rebuild` のあと再起動が必要
- **gui** — ディスプレイ無し時は `cage` で単一 GUI アプリを起動（`gui firefox` など）。引数なしは `apps` を起動
- **apps** — `fzf` アプリ一覧（`gui` 経由起動）。TTY やシェルから利用可。Sway の Super+D は rofi

## 日本語入力（Meltype / Fcitx5）

[Meltype](https://github.com/yksr-melt/Meltype)（Linux プレビュー）を **Fcitx5** アドオンとして入れています（Sway Wayland 向け）。IME グループは **Meltype のみ**（`fcitx5-mozc` / `keyboard-jp` は入れない）。ローマ字の日本語と英語を自動で打ち分けます。

- **Super+Space**: Fcitx Trigger（IME 有効 ⇔ 無効）。グループが Meltype だけなので、どちらもエンジンは Meltype のまま
- Meltype 内の英数 ⇔ 日本語: **半角/全角**（Fcitx の Trigger には割り当てない。ChatGPT 等 Electron で直接入力に落ちて戻せなくなるのを防ぐ）
- **z + 記号 / hjkl**: `zl`→`→`、`zh`→`←`、`zj`→`↓`、`zk`→`↑`、`z/`→`・`、`z.`→`…` など（Meltype 1.4+、既定 ON）
- 学習・設定: `~/.local/share/Meltype`
- 詳細設定: **Fcitx5 設定**（`fcitx5-configtool`）
- プロファイル／config: NixOS モジュールが生成する INI を、Home Manager が `~/.config/fcitx5/{profile,config}` へシンボリックリンクする。Fcitx は `~/.config` を `/etc/xdg` より先に読むので、古いユーザコピー（`keyboard-jp` や半角/全角 Trigger）が勝たない。リンク先はストアで読み取り専用。変更は `modules/nixos/common.nix` の `i18n.inputMethod.fcitx5.settings`
- **Cursor / ChatGPT** など Electron: `NIXOS_OZONE_WL=1` と Wayland IME フラグ。`ShareInputState=All` でフォーカス間の active/inactive ずれを抑える。適用後はアプリを**完全終了**してから開き直す
- 適用後: `rebuild` してから **fcitx5 再起動**（例: `fcitx5 -d --replace`）かセッション再ログイン

## フォント

比例フォントの第一候補はヒラギノです。fontconfig の既定は家族名のリストで、入っていない名前は飛ばします。ヒラギノが無い評価（他のマシン、`nix flake check`、`--impure` なし）では次のフォントが使われます。

- sans / 等幅の日本語: `Noto Sans CJK JP`（`noto-fonts-cjk-sans`）
- serif: `Noto Serif CJK JP`（`noto-fonts-cjk-serif`）
- 等幅のラテン: `JetBrainsMono Nerd Font`（Ghostty も 12pt）

ヒラギノは flake input にしていません。`path:` 入力は、そのディレクトリが無いマシンで flake 全体の評価が失敗するためです。

有効にする手順:

1. OTF を ASCII 名で `/home/mitac/Documents/hiragino-otf/` に置く（`~/Documents/ヒラギノ.zip` を展開。パスは `lib/machine.nix` の `hiraginoDir`）
2. `--impure` でビルドする。`rebuild` はこのディレクトリがあるときだけ `--impure` を付けます

仕組み: `builtins.pathExists` は pure 評価では flake の外の絶対パスを読めず、結果は false です。`--impure` のときだけ実在を見て、ある場合だけ `builtins.path` でストアへコピーし `fonts.packages` に足します。第一候補は sans `Hiragino Kaku Gothic ProN` / serif `Hiragino Mincho ProN` のままです。

waybar の CSS が名指しするのは `JetBrainsMono Nerd Font` だけです。日本語の字形は CSS では指定せず、fontconfig の既定（ヒラギノ、無ければ `Noto Sans CJK JP`）が埋めます。waybar のためだけに CJK フォントは足していません。

Nerd Font のアイコンが空白に見える場合: `fc-cache -rf` を実行し、ログアウトして再ログインします。

## ターミナル

既定は **Ghostty**（`programs.ghostty`）。**Ctrl+Alt+T** / **Super+Return** で開きます。
`TERMINAL=ghostty` も Home Manager で設定しています。

## タッチパッド

ナチュラルスクロールはオフ（従来型: 指を上 → 内容が上）。キーボード入力中もタッチパッドは有効（`dwt = disabled`）。右クリックは **2本指タップ／2本指押し**（`tap` + `click_method = clickfinger`）。端を押すソフトボタン領域は使わない。Sway の `input type:touchpad`（`home/sway.nix`）。

## クリップボード履歴

`cliphist`（systemd user の `wl-paste --watch`）+ `clipboard-history`（rofi → 選択で貼り付け）。呼び出しは **Super+V**。

## /home の暗号化バックアップ

`modules/nixos/backup.nix` は、ユーザーのホームと**一部のシステム状態**を暗号化して **Google Drive** へバックアップします。

- **restic** — `/home/mitac` に加え、NetworkManager の Wi-Fi プロファイル・Bluetooth ペアリング・Cloudflare WARP 状態・Tailscale ノード状態の一時コピー（staged）を暗号化・重複排除してスナップショット保存します。
- **rclone** — Google Drive バックエンド（restic リポジトリ: `rclone:gdrive:restic/mitac-home`）。
- **Bitwarden (`rbw`)** — restic の暗号化鍵を保持します。実行時に `RESTIC_PASSWORD_COMMAND=rbw get restic-home` 経由で鍵を取得するため、**鍵データはディスク上にも Nix ストアにも書き込まれません**。`rbw` 自体の宣言的設定は `home/programs.nix`（`programs.rbw`）にあります。

日次の `systemd` タイマー（`restic-backups-home.timer`）がバックアップを実行し、古いスナップショットを整理します（`--keep-daily 7 --keep-weekly 5 --keep-monthly 12`）。グラフィカルセッションへのログイン中は **Sway の waybar** に進捗（`バックアップ N%`、`$XDG_RUNTIME_DIR/restic-home-status` 経由）が表示され、開始・完了（または失敗）が mako 通知で知らされます。

### 初回セットアップ（秘密情報は git / Nix ストアに含めない）

1. rebuild の前に**識別子を編集**します。
   - `home/programs.nix`: `programs.rbw.settings.email` → 自分の Bitwarden メールアドレス。
   - `modules/nixos/backup.nix`（任意）: `repository`、`bitwardenItem`、`paths`。
2. **rebuild**: `sudo nixos-rebuild switch --flake .#vaio`（または `.#chromebook`）。
3. **自分専用の Google Drive OAuth クライアントを作成**（必須: rclone 共有の `client_id` は 2026 年に廃止予定であり、共有クォータでは復元が極端に遅くなるため）。[Making your own client_id](https://rclone.org/drive/#making-your-own-client-id) も参照してください。
   1. [Google Cloud Console](https://console.cloud.google.com/) → 新規プロジェクトを作成（例: `rclone-mitac`）。
   2. **APIs & Services → Library**（API とサービス → ライブラリ）→ **Google Drive API** を有効化。
   3. **OAuth consent screen**（OAuth 同意画面）→ User type で **External**（外部）を選択 → アプリ名とメールアドレスを設定。
   4. **Data Access**（データアクセス）→ 次のスコープを追加:
      - `https://www.googleapis.com/auth/docs`
      - `https://www.googleapis.com/auth/drive`
      - `https://www.googleapis.com/auth/drive.metadata.readonly`
   5. **Audience**（対象）→ **+ Add users** → テストユーザーに自分の Google アカウントを追加。
   6. **Clients → Create OAuth client**（クライアント → OAuth クライアントを作成）→ Application type で **Desktop app**（デスクトップ アプリ）を選択して作成。
      表示された **Client ID** と **Client secret** を控えます（秘密情報のため絶対にコミットしない）。
   7. **Audience → Publish app**（対象 → アプリを公開、Testing から移行）。**無人バックアップには必須です** — Testing 状態のままだとリフレッシュトークンが約 **7 日ごと** に失効します（`invalid_grant` / `rclone config reconnect gdrive:`）。個人利用（単一ユーザー）であれば公開にあたって Google の審査（Verification）は不要です（再接続時に一度「未確認のアプリ」警告が出ますがそのまま進めて問題ありません）。
      **Publish** がグレーアウトされている場合、Google は**自身が所有するドメイン**（Search Console で所有権確認済み）でのブランディング設定を要求します。`github.io` は拒否されることが多いため、次のように設定します。
      - アプリ名（完全一致）: `restic Home Backup`
      - ホームページ: https://restic-oauth.mitac.f5.si/
      - プライバシーポリシー: https://restic-oauth.mitac.f5.si/privacy.html
      - 承認済みドメイン: `mitac.f5.si`（GCP プロジェクトと同じ Google アカウントで [Search Console](https://search.google.com/search-console) のドメインプロパティとして所有権を確認）
      保存後、所有権確認直後の場合は最大 24 時間待ち、ブランディング再審査を **「問題は修正した」** でリクエストしてください（指摘事項は実際の設定不備によるものなので、「指摘に誤りがある」は選ばないこと）。その後 **Audience → Publish** を押します。
      参考: [rclone: Making your own client_id](https://rclone.org/drive/#making-your-own-client-id)
4. **対話式セットアップを実行**（rclone `gdrive` OAuth → Bitwarden 鍵 → 初回バックアップ。プロンプトは英語表示）:
   ```bash
   backup setup          # restic-home-setup と同じ
   ```
   rclone から `client_id` / `client_secret` を尋ねられたら、手順 3 で取得した値を貼り付けます（**空欄のままにしないこと**）。手動で設定／再接続する場合は次のとおりです。
   ```bash
   # 新規リモート作成
   rclone config
   # n → name: gdrive → storage: drive
   # client_id>   <自分の Client ID>
   # client_secret> <自分の Client secret>
   # scope> 1 (full drive) → ブラウザで OAuth 認証

   # トークン失効 / 週次の invalid_grant 時（OAuth アプリ公開後に実施）:
   backup reconnect
   backup about          # 疎通確認

   # 既存リモートが共有 client_id のままの場合:
   backup reconnect
   # または: rclone config → e (edit) → gdrive → client_id/secret を設定 → replace token (Y)
   ```
   続いて Bitwarden の解錠と初回バックアップを実行します。
   ```bash
   rbw login && backup unlock-key
   rbw generate 40 restic-home   # パスワード欄 = restic 暗号化鍵
   backup run
   backup log
   ```

### OS ビルド前に実機へ復元

既存バックアップを実機の NixOS へ戻すときは、`mitac` ユーザーでこのリポジトリから実行します。OS の再ビルドは不要です。

```bash
./scripts/restore-on-nixos.sh
# 別ディスクに復元する場合（親ディレクトリは作成済み、復元先自体は未作成）:
./scripts/restore-on-nixos.sh /mnt/restore-disk/mitac-restored
```

不足するツールは `nix shell` で取得します。既存の `gdrive` 接続設定と Bitwarden に保存済みの **`restic-home` 鍵**を利用します。認証設定がまだない実機では、先に次のシェル内で準備してください。

```bash
nix --extra-experimental-features 'nix-command flakes' shell \
  nixpkgs#rclone nixpkgs#rbw nixpkgs#pinentry-curses --command bash
rclone config                   # リモート名 gdrive、種類 Google Drive、自分の OAuth client_id/secret
rbw config set email YOUR_BITWARDEN_EMAIL
rbw config set base_url https://api.bitwarden.eu
rbw config set identity_url https://identity.bitwarden.eu
rbw config set pinentry pinentry-curses
rbw login
rbw unlock
exit
./scripts/restore-on-nixos.sh
```

既存の設定・ログインがある場合は再設定不要です。上の例はこのリポジトリと同じ Bitwarden EU 向けです。`RCLONE_CONFIG` があればその設定を使い、未指定なら `~/.config/rclone/rclone.conf`、それもなければ rclone の既定設定を使います。鍵は `rbw get restic-home` で取得し、`RESTIC_PASSWORD_FILE` / `RESTIC_PASSWORD_COMMAND` などが設定済みならそれを優先します。復元には**元の鍵**が必要です。新しい鍵の生成や `backup setup` は行わないでください。Google が `invalid_grant` を返す場合は、上のシェルで `rclone config reconnect gdrive:` を実行します。

スクリプトは非 CJK の TTY コンソールでも文字化けしないようすべて英語でメッセージを出力します。最新スナップショットを固定し、必要容量と空き容量を確認して、全体を `/var/tmp/restore-mitac-YYYYMMDD-HHMMSS/` へ復元します。`restic restore --verify` の成功後に `Restore and verification completed.` を表示します。既存ディレクトリへの上書きはせず、中断・失敗時のファイルも残します。

- ホーム: `復元先/home/mitac/`
- フォント: `復元先/home/mitac/Documents/hiragino-otf/`
- Wi-Fi / Bluetooth / WARP / Tailscale の保存状態: `復元先/run/restic-backups-home/system/`

実際の `/home` や `/etc` への反映は、復元内容と現在のファイルを確認してから行います。ヒラギノを使うなら、OS ビルド前に OTF を `/home/mitac/Documents/hiragino-otf` に置き、`rebuild`（ディレクトリがあるとき `--impure`）してください。置かない場合の既定は Noto CJK です。復元対象はバックアップに含まれる範囲で、`MySettings`、キャッシュ、ゲーム本体などの除外対象や `/etc/shadow` は含まれません。使い方は `./scripts/restore-on-nixos.sh --help` でも確認できます。

### 復元・確認（適用済みの環境）

このモジュールはセットアップ、systemd ユニット、rclone 確認、および restic（リポジトリ／Bitwarden パスワードコマンド設定済み）をまとめて扱う `backup` CLI（`backup --help`・`backup setup` の対話出力は TTY 互換のため英語表示）を導入します。`restic-home-setup` も `backup setup` のエイリアスとして残っています。

```bash
backup                 # 使い方
backup setup
backup run && backup log
backup snapshots
backup restore latest --target /tmp/restore
```

システム状態は `/tmp/restore/run/restic-backups-home/system/` 配下に展開されます。

```bash
# Wi-Fi
sudo cp /tmp/restore/run/restic-backups-home/system/nm-connections/* \
  /etc/NetworkManager/system-connections/
sudo chown root:root /etc/NetworkManager/system-connections/*
sudo chmod 600 /etc/NetworkManager/system-connections/*
sudo nmcli connection reload

# Bluetooth ペアリング情報
sudo cp -a /tmp/restore/run/restic-backups-home/system/bluetooth/. \
  /var/lib/bluetooth/
sudo chown -R root:root /var/lib/bluetooth
sudo systemctl restart bluetooth

# Cloudflare WARP デバイス登録情報
sudo cp -a /tmp/restore/run/restic-backups-home/system/cloudflare-warp/. \
  /var/lib/cloudflare-warp/
sudo chown -R root:root /var/lib/cloudflare-warp
sudo systemctl restart cloudflare-warp 2>/dev/null || true

# Tailscale ノード状態（ログイン／鍵）
sudo cp -a /tmp/restore/run/restic-backups-home/system/tailscale/. \
  /var/lib/tailscale/
sudo chown -R root:root /var/lib/tailscale
sudo systemctl restart tailscaled
```

Google Drive からの復元でレート制限にかかる場合は、先にリポジトリをローカルへコピーしてからディスクから復元します。

```bash
rclone copy gdrive:restic/mitac-home /var/tmp/restic-mitac-home \
  --fast-list --transfers 4 --checkers 8 --tpslimit 8 --drive-chunk-size 64M
restic restore latest \
  --repo /var/tmp/restic-mitac-home \
  --password-command 'rbw get restic-home' \
  --target /tmp/restore
```

### 注意事項

- バックアップはユーザー `mitac` で実行されるため、成功させるには `rbw` が**ロック解除済み／到達可能**である必要があります。グラフィカルセッション内で `rbw-agent` をアンロック状態に保っておくのが推奨です。タイマー実行時に Vault がロックされている場合、パスワードコマンドはセッションの D-Bus / Wayland（または X11）を取り込んで `pinentry-qt` で入力を促します。セッションがない環境では先に `backup unlock-key` でアンロックしてから `backup run` を実行してください。
- root のみ読める領域（Wi-Fi、Bluetooth、Cloudflare WARP、Tailscale）は root 権限の `ExecStartPre` で `/run/restic-backups-home/system/…` へ一時コピーされ、停止時に削除されます。`/etc/shadow`（ログインパスワード）は**バックアップされません**。`~/MySettings`（`.git` や未コミットの作業を含む flake チェックアウト一式）は `/home/mitac` の他のファイルと**一緒に含まれ**、復元後は `/tmp/restore/home/mitac/MySettings` に展開されます。
- 再生成可能な大容量データは除外されます（Steam クライアント／ランタイムとゲーム本体 ※ `userdata` / `compatdata` のセーブデータは保持、Cursor の agent-worker バイナリとキャッシュ、Vivaldi のキャッシュ／拡張機能／WebStorage、Firefox の `storage`）。
- `/home` **全体**（複数ユーザー）をバックアップしたい場合は、サービスの実行ユーザーを `root` に変更し、`root` 側の `rclone` / `rbw` を設定してください。
- rclone の OAuth トークンと Bitwarden ログイン情報は `~/.config` 配下に保存され、このリポジトリには一切含まれません。

## Neovim 設定

[LazyVim](https://github.com/LazyVim/LazyVim) スターター構成（NixOS 向けに調整）。

| パス | 役割 |
|------|------|
| `home/nvim/init.lua` | `config.lazy` の読み込み |
| `home/nvim/lua/config/` | options / keymaps / autocmds / lazy セットアップ |
| `home/nvim/lua/plugins/` | 追加・上書き用のプラグイン仕様（`nix.lua` で Mason 無効化） |

- **lazy.nvim** と LazyVim のコアプラグインは `pkgs.vimPlugins` を `linkFarm` したディレクトリ（`home/lazy-plugins.nix`）。lazy の `dev.path` がそこを見る。`dev.fallback` はオフ、`install.missing` もオフなので、起動時に git clone しない
- バージョンは nixpkgs のピン（`flake.lock`）で決まる。`lazy-lock.json` はローカルプラグインを記録しない。パスは読み取り専用の `~/.config/nvim` を避けて `~/.local/state/nvim/lazy-lock.json` のまま
- treesitter のパーサは `nvim-treesitter.withPlugins` の `parser/*.so` を `install_dir`（`~/.local/share/nvim/nix/treesitter`）に置く。LazyVim はそこにある言語を `TS.install` しない。言語を足すときは `home/lazy-plugins.nix` のリストを変える
- LSP / formatter は Mason ではなく `programs.neovim.extraPackages`（`lua-language-server`、`stylua`、`ripgrep`、`fd`）。Mason は無効のまま

## VAIO（Intel 第8世代以降）

| 項目 | 詳細 |
|------|------|
| Flake ターゲット | `.#vaio`（`hosts/vaio/default.nix`） |
| CPU / GPU | Intel 第8世代以降（Core i / Core Ultra iGPU）。`intel-media-driver` + `LIBVA_DRIVER_NAME=iHD` + `sof-firmware`（`modules/nixos/laptop/graphics.nix`） |
| オーディオ | **PipeWire + WirePlumber**（ALSA / 32bit ALSA / `pipewire-pulse` / JACK 互換）+ Bluetooth（`modules/nixos/vaio/audio.nix`）。Chromebook 用の PulseAudio / `hw:0,0` 固定・`max98373` ミキサは不使用 |
| キーボード・OOM | `keyd` により **Ctrl+Alt+Del**（**Ctrl+Alt+Backspace** も可）で手動 OOM killer（SysRq-f）＋ libinput 内部キーボード扱い。Chromebook 用 `cros` 最上段変換は適用しないため、`F1`–`F12` は通常のファンクションキーとして動作（`modules/nixos/laptop/input.nix`） |
| 電源・コード | `zram`（100% / zstd）・`thermald`・`auto-cpufreq`・`power-chords`（全 `"Power Button"` ACPI ノードを監視: 短押し=suspend / 長押し≈2.5s=poweroff / **電源+F1=強制ログアウト** / **電源+F2=再起動**）。Chromebook 専用 `/dev/cros_ec` Type-C 制御はロードしない |
| バックライト | Waybar `backlight` はデバイス名固定なし（`intel_backlight` 等を自動検出） |

### VAIO オーディオ確認

```bash
pactl info | grep 'Server Name'
# "Server Name: PulseAudio (on PipeWire ...)" を期待

pactl list short sinks
# スピーカー／HDMI／Bluetooth シンクが見えること

# 緊急停止（ミュート + PipeWire / WirePlumber 再起動）:
audio-panic
```

## Chromebook — ASUS CX5500FE / delbin

| 項目 | 詳細 |
|------|------|
| Flake ターゲット | `.#chromebook`（`hosts/chromebook/default.nix`。後方互換エイリアス `.#mitac` も同一） |
| ボード | `delbin`（`DELBIN_XHVI`） |
| プラットフォーム | `volteer`（Intel Tiger Lake） |
| GPU | Iris Xe（i3-1115G4）。`intel-media-driver` + `LIBVA_DRIVER_NAME=iHD`（`modules/nixos/laptop/graphics.nix`） |
| オーディオ | SOF + `sof-rt5682` / `max98373`（`alsa-ucm-conf-cros` + `sof-firmware`） |
| キーボード | [cros-keyboard-map](https://github.com/WeirdTreeThing/cros-keyboard-map) 相当の `keyd`（delbin physmap）。最上段は ChromeOS キー。**Search+最上段**で F1–F10。tuigreet セッション一覧は **Search+3つ目のキー（zoom/全画面）**。**Ctrl+Alt+Del**（内蔵は **Ctrl+Alt+Backspace**）で手動 OOM killer。電源コード: 短押し=suspend / 長押し≈2.5s=poweroff / **電源+Back=強制ログアウト** / **電源+Refresh=再起動**（`power-chords`） |
| Flip | タブレットモード向け libinput quirk `ModelTabletModeNoSuspend=1` |
| USB-C 電力 | `chromebook-typec-prefer-sink`: 空きポートは FORCE_SINK（壁充電器／モババッ受電）、スマホ(UFP)→ source、AC給電中の他ポート→ source。udev は partner 追加時のみ（typec CHANGE はループ防止で除外） |
| ストレージ / Btrfs | 既定の `hardware-configuration.nix` は `ext4`。`btrfs`（`compress=zstd:1`）へ切り替える場合は「[Chromebook を btrfs 透過圧縮でクリーン再インストール](#chromebook-を-btrfs-透過圧縮でクリーン再インストール)」を参照 |

### Chromebook オーディオ確認

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
- sof-rt5682 は UCM Mic/DMIC 探索で `module-alsa-card` が落ちるため、**`hw:0,0`（Speaker）/ `hw:0,1`（Headset mic）を直接**バインド（`module-udev-detect` は無効）
- `chromebook-alsactl-init` / レジュームに `ALSA_CONFIG_UCM2`（cros マージ + `sofrt5682` エイリアス）を明示。これがないと `alsactl init` が毎回 -2 になる
- 起動／レジューム時に `alsactl init` + `chromebook-speaker-levels apply`（max98373 Digital/Spk）
- 緊急停止: `audio-panic`（`chromebook-speaker-levels mute`）

```bash
pactl list short sinks   # speaker が見えること
speaker-test -c 2 -t wav -l 1
```

dmesg の `DMIC16kHz` IPC `-22` は NHLT に DMIC が無い場合の既知ノイズで、スピーカー不具合とは別件です。

### Chromebook キーボード確認

最上段キーは Back / Forward / Refresh / Fullscreen / Brightness / Volume として動作するはずです（単なる F1–F10 ではありません）。

## VA-API / Parsec 確認（Chromebook / VAIO 共通）

```bash
vainfo
# iHD ドライバと H.264 の EncSlice / VLD が出ることを期待
```

Parsec を開き直してハードウェアエンコーダーが選べるか確認します。

### Parsec over Tailscale（ホテル等で -6023 のとき）

Parsec は Tailscale の `100.64/10` を LAN とみなさないことが多い。ホスト（Windows / `galleria-mitac` = `100.102.102.53`）側で接続先 IP を強制する。

**1. ホスト（一度だけ）** — Parsec を完全終了し、`%AppData%\Parsec\config.txt` に次を追加してから再起動（自動で `config.json` へ移行される）:

```text
app_custom_address = 100.102.102.53
```

**2. クライアント（このマシン）**

```bash
parsec-ts                 # WARP 切断 → galleria-mitac へ ping → Parsec 起動
# またはホスト名指定: parsec-ts galleria-mitac
```

外出先で自宅 LAN（`192.168.1.0/24`）そのものへも行きたいときだけ:

```bash
ts-home-routes on         # galleria が広告するサブネットを受け取る
# …作業…
ts-home-routes off        # 帰宅後は必ず off（オンのまま自宅 Wi-Fi に繋がると LAN が壊れる）
```

常時 `--accept-routes` は入れない（自宅で同じ `192.168.1.0/24` を受けて Wi-Fi が死ぬため）。

## 構成

```
flake.nix
lib/machine.nix                   # 作業コピー・フォールバックホスト・ヒラギノパス設定
hosts/chromebook/                 # delbin Chromebook エントリ + hardware-configuration.nix
hosts/vaio/                       # VAIO エントリ + hardware-configuration.nix（要実機生成）
modules/nixos/common.nix          # locale、ユーザー、Meltype/Fcitx5、フォント
modules/nixos/desktop.nix         # sway + greetd + console-gui + portals + XKB/印刷
modules/nixos/sway.nix            # Sway システム側（greetd 既定セッション等）
modules/nixos/greetd.nix          # tuigreet（Sway のみ）
modules/nixos/console-gui.nix     # gui / apps（Sway ランチャー等）
modules/nixos/laptop.nix          # ノート PC 共通ハードウェア集約（./laptop/*）
modules/nixos/laptop/             # graphics（Intel iHD + SOF）/ input（keyd OOM）/ power（zram + thermald + auto-cpufreq + power-chords）
modules/nixos/vaio.nix            # VAIO 固有集約（./vaio/*）
modules/nixos/vaio/               # audio（PipeWire + WirePlumber + Bluetooth）
modules/nixos/chromebook.nix      # delbin Chromebook 固有集約（./chromebook/*）
modules/nixos/chromebook/         # audio（PulseAudio + UCM）/ power（Type-C EC）/ input（cros keyd + Flip）
modules/nixos/backup.nix          # 暗号化 /home → Google Drive バックアップ（restic / rclone / rbw）
modules/nixos/release.nix         # system.nixos.tags（世代ラベルのスラッグ）
home/mitac.nix                    # HM エントリ（identity + imports）
home/flake-tools.nix              # repoPath / flakeHost / scripts（ストア経由）
home/shell.nix                    # bash エイリアス / rebuild / audio-panic / runbtop
home/programs.nix                 # git / rbw / neovim / mime / 起動音 / 共通パッケージ
home/lazy-plugins.nix             # nixpkgs 由来 LazyVim プラグイン + treesitter パーサ
home/clipboard.nix                # cliphist + clipboard-history
home/sway.nix                     # Sway（waybar/mako/swayidle・rofi・jp・チートシート）
home/nvim/
```
