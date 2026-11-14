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

> **初回設定は Graphical ISO の日本語 LXQt 環境で行うのがおすすめ**: `ja_JP.UTF-8` と `Asia/Tokyo`・日本語キーボードを選べば日本語表示（フォント）・Firefox・GUI 端末（QTerminal）・クリップボードが初期状態から使えるため、GitHub 認証・Bitwarden（`rbw` + GUI `pinentry-qt`）・Google Drive OAuth の操作や長い文字列の扱いが格段に楽になります（日本語入力 IME の Meltype はこの flake 適用後に有効になります）。Minimal ISO 等の GUI 無しコンソール（TTY）を直接使う場合のみ、コンソールフォントに日本語グリフが無いため ISO 既定の英語（`en_US.UTF-8`）のままで進めてください（`modules/nixos/greetd.nix` の `tuigreet` 時刻表示も同理由で ASCII 維持）。なお、この flake は Calamares が生成する `/etc/nixos/configuration.nix`（一時的な **LXQt / LightDM 設定**）を import しないため、設定取得・復元後に `nixos-rebuild switch --flake` と再起動を行えばクリーンに **greetd（`tuigreet`）+ Sway 専用環境**へ切り替わります。

### 0. USB メディアの作成と起動

1. [NixOS ダウンロードページ](https://nixos.org/download/) から **Graphical ISO**（GUI インストーラ＆Live デスクトップ付き・推奨）または **Minimal ISO**（CLI のみ）を取得し、USB メモリへ書き込む。
2. 対象機の UEFI 設定で Secure Boot を無効にし、USB から **UEFI モード**で起動する（Chromebook は事前に MrChromebox 等の UEFI ファームウェアを導入しておく）。

### 1. NixOS の導入（2 パターン）

#### パターン A: Graphical ISO（日本語・LXQt）で導入してから復元・適用（推奨）

既存バックアップを `./scripts/restore-on-nixos.sh` で復元する場合（`mitac` ユーザーで実機 NixOS 上から実行する設計）や、ブラウザー／GUI 端末／`pinentry-qt` を使いながら初期設定を進めたい場合はこの手順が最も楽です。

1. Live 環境で Wi-Fi 等へ接続し、**Install NixOS**（Calamares）を起動する。
2. インストーラで以下を設定してインストールする：
   - 言語／ロケール（Welcome / Location）: **日本語**（`ja_JP.UTF-8`）、タイムゾーン **Asia/Tokyo**
   - キーボード（Keyboard）: **Japanese** を選択
   - ユーザー名: **`mitac`**（`lib/machine.nix` の `/home/mitac/MySettings`・各種設定と一致させる）＋ 任意のパスワード
   - デスクトップ環境: **LXQt** を選択（軽量でありながら日本語表示・GUI 端末 QTerminal・Firefox・Qt ベースの `pinentry-qt` が使える。後の flake 適用＋再起動で **greetd + Sway** へ置き換わります）
   - パーティション: ディスク消去（UEFI / GPT）を選択。swap は **No swap**（`zramSwap` を使用）でも問題ない
3. 完了後に USB を抜いて再起動し、日本語 **LXQt** デスクトップへ `mitac` でログインする。
4. 端末（QTerminal 等）を開き、作業コピーを `~/MySettings` へ取得する（初回環境のため `nix-shell` で `git` を一時利用）：
   ```bash
   nix-shell -p git --run \
     'git clone -b main https://github.com/mitac31709/MySettings.git ~/MySettings'
   cd ~/MySettings
   ```
5. **（既存バックアップまたは agenix 鍵を復元する場合）** OS ビルドの前に「[OS ビルド前に実機へ復元](#os-ビルド前に実機へ復元)」の手順で `./scripts/restore-on-nixos.sh`（別端末のバックアップや初期化後の新端末構築では `--from <chromebook|vaio|mitac> --new-device`）を実行する。不足ツール（`restic` / `rclone` / `jq` / `python3` / `rbw` / `pinentry-qt`）を自動取得し、**`rbw` で Bitwarden（`restic-home` および登録済みなら `agenix-master-key`）を自動読込**して Google OAuth・暗号化パスワード・`/etc/agenix/master.key` を自動配置します（`/home` バックアップを使わず **agenix マスター鍵だけを復元**する場合は `./scripts/restore-on-nixos.sh --agenix-only`）。初回は `rbw` 設定・ログインのみ案内に従います（`restic-home` 未登録なら対話入力・ブラウザー OAuth へフォールバック）。バックアップ内の `/home/mitac`（`/home/mitac/Documents/hiragino-otf/` を含む）およびシステム状態が**元の位置へ復元**されます（`/etc/agenix/master.key` やシステム状態の反映時のみ `sudo` パスワード入力が必要。今回新規取得・更新した `~/.config/rclone/rclone.conf` は保持され、`--new-device` 指定時は既存の `~/MySettings`・`rbw`・`rclone.conf` を保持したうえで Tailscale/WARP/Bluetooth・各種端末 ID/トークン・Wi-Fi の NIC 名縛りを初期化し、複数端末の同時稼働で競合しない状態にします）。展開確認のみしたい場合は `./scripts/restore-on-nixos.sh --new-device /var/tmp/restore-check` のように展開先を引数指定します。
6. 実機の `hardware-configuration.nix` を生成し、flake を適用する（対象は `vaio` または `chromebook`）：
   ```bash
   # VAIO の場合（Chromebook は hosts/chromebook/hardware-configuration.nix と .#chromebook）
   sudo nixos-generate-config --show-hardware-config > hosts/vaio/hardware-configuration.nix

   # 適用（~/Documents/hiragino-otf が既にある場合は `--impure` を追加）
   sudo NIX_CONFIG='experimental-features = nix-command flakes' \
     nixos-rebuild switch --flake .#vaio
   ```
7. 完了後、カーネル／bootvine／`greetd`／Sway セッションへクリーンに切り替えるため `sudo reboot` する。
   （※ この flake は一時的な LXQt を含まないため、再起動後は `tuigreet` + Sway のみになります。後で旧世代の LXQt ストアパスを掃除したい場合は `sudo nix-collect-garbage -d` を実行できます）

#### パターン B: Live USB（CLI）から `nixos-install --flake` で直接導入

GUI インストーラを経由せず、USB のターミナルから直接この flake の環境を書き込む手順です（Graphical ISO の GUI 端末でも、Minimal ISO の TTY コンソールでも実行できます。Live 環境上には `/home/mitac/Documents/hiragino-otf` が無いため、初回は Noto CJK でビルドされます）。

1. Minimal ISO の TTY を使う場合だけ、文字化け防止のためロケールは ISO 既定の英語（`en_US.UTF-8`）のまま（Graphical ISO の端末なら日本語のまま可）、必要なら日本語配列とネットワークを設定する：
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
4. （任意・`secrets/*.age` を利用済みの場合）`rbw` または USB メディアから共通マスター鍵を `/mnt/etc/agenix/master.key`（`0400` / `root:root`）へ先行配置しておくと、次の `nixos-install` 直後から Wi-Fi・Tailscale・GitHub・SSH・backup 用シークレットが有効になります（再起動後に `./scripts/restore-on-nixos.sh --agenix-only` または `secrets bootstrap` で配置して `rebuild` することも可能です）。
   ```bash
   # 例: USB 等から手動配置する場合
   sudo install -d -m 0700 -o root -g root /mnt/etc/agenix
   # sudo install -m 0400 -o root -g root /path/to/master.key /mnt/etc/agenix/master.key
   ```
5. flake でインストールする（対象は `#vaio` または `#chromebook`）：
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

再起動後の `tuigreet` でユーザー `mitac` を選んでログインすると **Sway** が起動します（端末: **Ctrl+Alt+T** / **Super+Return**、IME トグル: **Super+Space**、英数⇔日本語: **半角/全角**、ランチャー: **Super+D** / **Alt+Space**）。秘密情報はこのリポジトリ内の **`secrets/*.age`（agenix）+ Bitwarden（`agenix-master-key`）** で宣言的に管理できます。未展開または未移行の項目のみ実機で設定します。

1. **宣言的シークレットの展開（`secrets/*.age` を利用している場合）**:
   - `/etc/agenix/master.key` をまだ配置していない場合は、まず `secrets bootstrap`（または `cd ~/MySettings && ./scripts/restore-on-nixos.sh --agenix-only`）を実行して Bitwarden の `agenix-master-key` を配置し、`rebuild` を実行します（`/run/agenix/*`・Wi-Fi プロファイル・`gh` 認証・SSH 鍵・backup 鍵・ユーザー環境変数が一括展開されます）。
2. **GitHub 認証（`gh`）**:
   - `gh-hosts.yml.age` を登録済みなら `~/.config/gh/hosts.yml` に自動展開済み（`gh auth status` で確認）。未登録・再認証時は `gh auth login` を実行し（`programs.gh` の `gitCredentialHelper` が有効なため、以降の `~/MySettings` での `git push` / `pull` にも使われます）、必要なら `secrets import-gh` で `.age` 化します。
3. **VPN（Tailscale / Cloudflare WARP）**:
   - Tailscale: `tailscale-authkey.age` が有効なら自動認証されます（自宅外でのみ必要な場合は `ts-home-routes off` のまま維持）。手動認証またはキー失効時は `sudo tailscale up --operator=mitac`
   - Cloudflare WARP: `warp-cli registration new` → `warp-cli connect`
4. **暗号化バックアップの復元または新規設定**:
   - **別機体の既存バックアップから復元する場合**: 「[OS ビルド前に実機へ復元](#os-ビルド前に実機へ復元)」のとおり `./scripts/restore-on-nixos.sh --from <chromebook|vaio|mitac> --new-device` を実行し（`rbw` で Bitwarden の `restic-home` と、登録済みなら `agenix-master-key` を自動取得・**新しい鍵を作らないこと**）、既存の `~/MySettings`・`rbw`・`rclone.conf` を保持しつつ `/home/mitac` と Wi-Fi 設定を復元する（端末 ID 衝突防止のため VPN/BT・P2P・トークン系ログインは新端末で初回サインイン）。各端末の自動バックアップ先はホスト別リポジトリ（`chromebook-home` / `vaio-home`）へ分離されているため、既存端末と同時運用しても互いにロックやスナップショットを上書きしません。`/etc/agenix/master.key` が配置され `restic-home-password.age` / `rclone-conf.age` がある環境では、自動バックアップは `rbw` 解錠不要で動作します（未移行時は `rbw unlocked` を確認し、必要なら `backup unlock-key` を実行）。
   - **新規でバックアップを初期構築する場合**: 「`/home の暗号化バックアップ` → `初回セットアップ`」に従い、GCP OAuth クライアント作成 → `backup setup` を実行し、Bitwarden の `restic-home` への保存および `secrets import-restic` / `secrets import-rclone` で agenix へ登録してから `backup run` を実行する。
5. **ヒラギノフォント（任意）**:
   `/home/mitac/Documents/hiragino-otf/` に OTF ファイルを配置し、`rebuild` を実行する（ディレクトリが存在すると `rebuild` が自動で `--impure` を付けて同梱します）。
6. **Vivaldi × ChatGPT 拡張（利用する場合）**:
   Vivaldi で Web Store 版を入れた後、`vivaldi-chatgpt-extension-patch` が `~/.local/share/vivaldi-chatgpt-extension` を生成するため、`vivaldi://extensions` で Store 版を無効化し、Developer mode → Load unpacked で同ディレクトリを読み込む。
7. **その他の任意設定と実機確認**:
   - **リモートビルダー**（`modules/nixos/remote-builder.nix`）: `id-wsl-builder.age` を登録済みなら `/run/agenix/id-wsl-builder-root`（`nix-daemon` 用）と `~/.ssh/id_wsl_builder` が自動展開されます（公開鍵は `galleria-mitac` 側へ登録）。未配置でもタイムアウト後にローカルビルドへフォールバック。待ち時間を省くなら `sudo nixos-rebuild switch --flake .#vaio --option builders ""` を実行。
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
2. `~/MySettings` に未プッシュの変更があれば確認して GitHub へプッシュする（`git status`）。`secrets/*.age` を利用中の場合もコミット・プッシュ済みか確認する（`secrets check --decrypt`）。
3. 再インストール後に `./scripts/restore-on-nixos.sh` が `rbw` で自動取得できるよう、Bitwarden の **`restic-home`** に暗号化パスワード（パスワード欄）と `client_id` / `client_secret` / `refresh_token`（メモ欄またはカスタムフィールド）が保存されており、agenix 利用時は **`agenix-master-key`** も保存されていることを確認しておく。あわせて、必要に応じて **別の USB メモリ等へ秘密ファイルを退避**しておくこともできます（Git には絶対に含めない）：
   - `~/.config/rclone/rclone.conf`（OAuth `client_id` / `client_secret`・トークン入り。これを戻せば `gdrive:` の取得を省略可能）
   - agenix 利用時は `/etc/agenix/master.key`（事前に `sudo cat /etc/agenix/master.key` 等で退避した場合、Bitwarden 経由なしでも即展開可能）
   - 未 agenix 移行でリモートビルダーを利用している場合は `~/.ssh/id_wsl_builder`

#### Live USB からの `btrfs` 導入（CLI 手順）

Calamares（Graphical ISO）で `btrfs` を選ぶと初回導入時は `compress=zstd:1` が付かないため、**Live USB のターミナル（Graphical ISO の GUI 端末、または Minimal ISO の CLI）から下記手順で最初からマウントオプション付きで導入する**のが確実です（最初の `nixos-install` 時点から `/nix/store` も圧縮されます）。

1. Live USB を UEFI 起動し、ネットワーク等を接続する（Minimal ISO の TTY を使う場合のみ、`en_US.UTF-8` のまま `loadkeys jp106` と `nmtui` を実行）：
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
5. （任意・USB 等に `master.key` を退避している場合）`/mnt/etc/agenix/master.key` を `0400` で配置し、`MySettings` の配置・`mitac` パスワード設定・所有者変更を行ってから再起動する：
   ```bash
   # 例: master.key を先行配置する場合
   # sudo install -d -m 0700 -o root -g root /mnt/etc/agenix
   # sudo install -m 0400 -o root -g root /path/to/master.key /mnt/etc/agenix/master.key

   sudo cp -a /tmp/MySettings /mnt/home/mitac/MySettings
   sudo nixos-enter --root /mnt
   passwd mitac
   chown -R mitac:users /home/mitac/MySettings
   exit

   sudo umount -R /mnt
   sudo reboot
   ```

#### 再起動後の復元と圧縮確認

1. `tuigreet` で `mitac` にログインする（日本語 Sway 環境が起動します。端末は **Ctrl+Alt+T**）。
2. USB へ退避した `~/.config/rclone/rclone.conf` がある場合は戻し（`chmod 600 ~/.config/rclone/rclone.conf`）、`cd ~/MySettings && ./scripts/restore-on-nixos.sh --from <vaio|chromebook|mitac> --new-device` を実行する（VAIO 側の最新環境を戻すなら `--from vaio --new-device`、旧来の単一バックアップから戻すなら `--from mitac --new-device`）。`rbw` の設定・ロック解除・同期を経て Bitwarden の `restic-home` から暗号化パスワードと（未配置なら）Google OAuth 情報が自動取得され、Bitwarden に **`agenix-master-key`** がある場合は `/etc/agenix/master.key` も同時に配置されます。
3. 上記コマンド（`--new-device` 付き）により、新しく生成済みの `~/MySettings`（新しい Btrfs UUID の `hosts/chromebook/hardware-configuration.nix`）や現在の `rbw` / `rclone.conf` を壊さずに `/home/mitac` と Wi-Fi 設定（NIC 名縛り自動解除済み）が復元され、Tailscale / Cloudflare WARP / Bluetooth・P2P 鍵・トークン系認証は他端末と競合しないよう初期状態にリセットされます（反映時のみ `sudo` が自動実行）。その後 `rebuild` を実行すると（agenix 利用時は）`/run/agenix/*` の各種シークレット・`restic`/`rclone` 設定・GitHub CLI 認証・SSH 鍵・Tailscale 鍵が宣言的に展開されます（未 agenix 環境では `rbw unlocked` / `backup unlock-key` と初回サインインを実施）。
4. 圧縮率と scrub タイマーを確認する：
   ```bash
   sudo compsize / /nix/store /home
   systemctl list-timers 'btrfs-scrub*'
   ```
5. `gh auth status` を確認し（`gh-hosts.yml.age` 未設定時のみ `gh auth login`）、`~/MySettings/hosts/chromebook/hardware-configuration.nix`（新しい Btrfs UUID / サブボリューム構成）をコミット・プッシュする。

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
- **シークレット管理（agenix × Bitwarden）** — `secrets/*.age` を NixOS（`modules/nixos/secrets.nix`）で `/run/agenix/*` へ復号し、共通マスター鍵 `agenix-master-key` のみを Bitwarden（`rbw`）で保持。`secrets` コマンド（`scripts/secrets-tool.sh`）で管理
- **暗号化バックアップ** — `restic` + `rclone` で `/home` を Google Drive へ。`agenix` 移行時は `/run/agenix/` 経由で自動無監視実行（未移行時・他端末リカバリ時は Bitwarden `rbw`）。詳細は下記。
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

## シークレット管理

`secrets/` 配下の暗号化ファイル（`.age`）と Bitwarden（`rbw`）を組み合わせた宣言的シークレット管理（`github:ryantm/agenix`）を採用しています。

### 設計（単一マスター鍵 + NixOS / Home Manager 連携）

- **全端末共通のマスター鍵**: Bitwarden の **`agenix-master-key`** 項目に保存した 1 本の `age` 秘密鍵を、各機体の `/etc/agenix/master.key`（`root:root` / `0400`）へ配置します（`age.identityPaths = [ "/etc/agenix/master.key" ]`）。新端末や SSD 再構築時も `secrets/agenix-rules.nix` の追記・`rekey` なしでそのまま複号できます。
- **インメモリ複号と権限分離**: `modules/nixos/secrets.nix` が NixOS 起動時に `/run/agenix/*`（`tmpfs`）へ複号します。平文は Nix ストアにも永続ディスクにも書き出されません。ユーザー領域向けの鍵・認証・環境変数は `home/secrets.nix`（Home Manager `osConfig` 参照）が `/run/agenix/*` へ安全にシンボリックリンク／ロードするため、`/etc/agenix/master.key` は **`root` 専用** のまま維持されます。
- **未移行状態の互換性**: `builtins.pathExists` による段階的有効化（`hasSecretFile`）になっているため、`secrets/*.age` がまだ存在しない状態でもシステム・バックアップは従来どおりエラーなく評価・動作します。

| 暗号化ファイル (`secrets/`) | 展開先（ランタイム） | 用途 |
|-----------------------------|----------------------|------|
| `restic-home-password.age` | `/run/agenix/restic-home-password` | `restic-backups-home` の自動実行用パスワード（Bitwarden `restic-home` にも同一パスワードを保持） |
| `rclone-conf.age` | `/run/agenix/rclone-conf` | `rclone` 用 Google Drive 設定（実行時に書き込み可能な `/run/restic-backups-home/rclone.conf` 等へコピーし OAuth 自動更新に対応） |
| `nm-connections.age` | `/run/agenix/nm-connections` | NetworkManager Wi-Fi プロファイル群（`nm-agenix-profiles.service` が `interface-name=` / `mac-address=` を除いて `/run/NetworkManager/system-connections/agenix-*.nmconnection` へ展開） |
| `tailscale-authkey.age` | `/run/agenix/tailscale-authkey` | Tailscale 事前認証／OAuth キー（`services.tailscale.authKeyFile`） |
| `id-wsl-builder.age` | `/run/agenix/id-wsl-builder-{root,user}` | `nix-daemon` 用ビルド鍵（`nix.buildMachines[0].sshKey`）兼 `~/.ssh/id_wsl_builder`（`secrets/id_wsl_builder.pub` があれば `~/.ssh/id_wsl_builder.pub` もリンク） |
| `id-ed25519.age` | `/run/agenix/id-ed25519` | 個人用 SSH 秘密鍵 `~/.ssh/id_ed25519`（`secrets/id_ed25519.pub` があれば `.pub` もリンク） |
| `gh-hosts.yml.age` | `/run/agenix/gh-hosts.yml` | GitHub CLI 認証 `~/.config/gh/hosts.yml` |
| `user-env.age` | `/run/agenix/user-env` | `export KEY=...` 形式の API トークン等（`bash` 初期化時読込 + `mitac-agenix-user-env.service` で `systemd --user` へ反映） |

### 初回セットアップ・日常運用（`secrets` CLI）

`scripts/secrets-tool.sh` が PATH 上の **`secrets`** コマンドとして同梱されています。

```bash
# 1. 初回のみ: マスター age 鍵を生成し Bitwarden (agenix-master-key) と /etc/agenix/master.key へ登録
secrets init

# 2. 現在のマシン上の秘密情報から .age を対話的に一括作成
secrets import
# 個別に取り込む場合:
#   secrets import-restic / import-rclone / import-ssh / import-gh / import-wifi
#   secrets set-tailscale-key

# 3. 暗号化ファイルをステージして複号検証し、OS に反映
git add secrets/
secrets check --decrypt
rebuild
```

- **新端末／再インストール時の展開**:
  - `./scripts/restore-on-nixos.sh --agenix-only`（または既存バックアップ復元と同時の `./scripts/restore-on-nixos.sh --from ... --new-device`）
  - すでに環境適用後なら `secrets bootstrap`（インストーラ等の `/mnt` 配下には `secrets bootstrap /mnt`）→ `rebuild`
- **個別編集・鍵ローテーション・状態確認**:
  - `secrets edit <name>`（例: `secrets edit user-env`、`name` は `secrets/agenix-rules.nix` の定義名または `.age` ファイル名）
  - `secrets status` / `secrets rekey` / `secrets check [--decrypt]`
- **リポジトリ公開設定・セキュリティ注意**:
  - 平文鍵ファイル（`secrets/*.key`, `secrets/*.plain`, `secrets/*.tmp`, `secrets/*~`）は `.gitignore` で除外しています。
  - `.age` 自体はマスター鍵なしでは複号できませんが、ファイル名と暗号文が Git 履歴に残るため GitHub リポジトリの可視設定（Private 推奨）や公開鍵ファイルの扱いに注意してください。
  - `restic-home` の暗号化パスワードと Google OAuth 情報は引き続き Bitwarden（`restic-home`）にも残すため、他端末から `agenix` を使わずにバックアップを検査・救出する運用も維持されます。

## /home の暗号化バックアップ

`modules/nixos/backup.nix` は、ユーザーのホームと**一部のシステム状態**を暗号化して **Google Drive** へバックアップします。

- **restic** — `/home/mitac` に加え、NetworkManager の Wi-Fi プロファイル・Bluetooth ペアリング・Cloudflare WARP 状態・Tailscale ノード状態の一時コピー（staged）を暗号化・重複排除してスナップショット保存します。
- **rclone** — Google Drive バックエンド（ホスト別 restic リポジトリ: `rclone:gdrive:restic/<host>-home` — `.#chromebook` は `chromebook-home`、`.#vaio` は `vaio-home`。旧単一構成の移行前バックアップは `mitac-home` に残ります）。各端末は共通の `gdrive:` リモートと下記の暗号化鍵を共有しつつリポジトリ自体が分かれているため、複数端末を同時起動してもロック競合や世代削除（`forget`）の干渉は起きません。
- **agenix × Bitwarden (`rbw`)** — `secrets/restic-home-password.age` と `secrets/rclone-conf.age` が有効な環境では `/run/agenix/restic-home-password`・`/run/agenix/rclone-conf` から復号して自動バックアップを実行するため、**タイマー実行に `rbw` のアンロック状態や GUI を要しません**（平文は `/run` のみで、`rclone.conf` は OAuth リフレッシュ対応のため一時ファイルへコピーして使用）。同一のパスワードと Google OAuth の `client_id` / `client_secret` / `refresh_token` は他端末復旧用として Bitwarden の **`restic-home`** にも引き続き保持します。未移行環境（`.age` 未配置時）は従来どおり `RESTIC_PASSWORD_COMMAND=rbw get restic-home` へフォールバックします。`rbw` 自体の宣言的設定は `home/programs.nix`（`programs.rbw`）にあります。

日次の `systemd` タイマー（`restic-backups-home.timer`）がバックアップを実行し、古いスナップショットを整理します（`--keep-daily 7 --keep-weekly 5 --keep-monthly 12`）。グラフィカルセッションへのログイン中は **Sway の waybar** に進捗（`バックアップ N%`、`$XDG_RUNTIME_DIR/restic-home-status` 経由）が表示され、開始・完了（または失敗）が mako 通知で知らされます。

### 初回セットアップ（秘密情報は平文で git / Nix ストアに含めない）

1. 必要に応じて識別子・設定を確認します。
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
4. **対話式セットアップを実行**（rclone `gdrive` OAuth → Bitwarden 鍵 → 初回バックアップ）:
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
   `backup setup`（ステップ 2 後）および `backup reconnect` の完了時に、`client_id: ...`・`client_secret: ...`・`refresh_token: ...` が画面へ表示されます。再インストール時や他端末リカバリに備え、表示された 3 項目をそのまま Bitwarden の **`restic-home`** のメモ欄（または同名カスタムフィールド）へコピーして保存／更新してください（`rbw edit` の暗号化破損リスクを避けるため自動書込みは行いません。また固定値 `gdrive` / `type = drive` / `scope = drive` の保存は不要です）。agenix を併用している場合は、あわせて案内されるとおり `secrets import-rclone`（初回パスワード設定時は `secrets import-restic` も）→ `git add secrets/` → `rebuild` を実行すると `/run/agenix/` 側も最新状態に同期されます。

   手動で agenix / Bitwarden 連携の初回バックアップを実行する場合は次のとおりです。
   ```bash
   rbw login && backup unlock-key
   rbw generate 40 restic-home   # パスワード欄 = restic 暗号化鍵
   secrets import-restic && secrets import-rclone   # agenix を有効化する場合
   git add secrets/ && rebuild
   backup run
   backup log
   ```

### OS ビルド前に実機へ復元

既存バックアップを実機の NixOS（日本語 LXQt 初期環境など）へ戻すときは、`mitac` ユーザー（`sudo` を付けず）でこのリポジトリから次を実行します。OS の再ビルド前でも実行できます。

```bash
# 同一端末の復元（ホスト名に応じた rclone:gdrive:restic/<host>-home を自動選択）:
./scripts/restore-on-nixos.sh

# 別端末のバックアップから新端末・再初期化後の環境へクリーン復元する場合:
./scripts/restore-on-nixos.sh --from vaio --new-device
# （旧単一リポジトリ mitac-home や Chromebook 側から戻す場合は --from mitac / --from chromebook）

# 中身の事前確認や別ディスクへの取り出しのみ行う場合（親は作成済み・展開先自体は未作成）:
./scripts/restore-on-nixos.sh --from vaio --new-device /mnt/restore-disk/mitac-restored
```

不足するツール（`restic` / `rclone` / `jq` / `python3` / `rbw`、`pinentry` 未導入時は GUI で `pinentry-qt`・非 GUI で `pinentry-curses`）は自動で `nix shell` から取得します。

`gdrive:` リモートまたは暗号化パスワードが未設定の場合は、対話確認（`[Y/n]`）のうえで **Bitwarden（`rbw`）からの自動取得**を行います（`RESTORE_NO_RBW=1` で `rbw` を使わず最初から手動入力にすることもできます）。

1. **Bitwarden（`rbw`）の自動構成・ログイン／ロック解除・同期**
   - `rbw` が未設定ならメールアドレス（`RBW_EMAIL`、既定 `mitac31709@gmail.com`）、公式 EU クラウドのエンドポイント（`home/programs.nix` と同一、`RBW_BASE_URL` 等で変更可）、および `pinentry`（GUI は `pinentry-qt`、非 GUI は `pinentry-curses`）を自動設定してから `rbw login && rbw unlock` と `rbw sync` を実行します（端末初回登録が必要な場合は回復メニューの `[r]` で `rbw register` → Personal API Key を入力可能）。
2. **`restic-home`（環境変数 `RBW_ITEM` で変更可）からの自動読込**
   - **暗号化パスワード**: パスワード欄を自動取得し、そのまま restic リポジトリの検証に使用します。
   - **Google Drive OAuth**: カスタムフィールド（優先）またはメモ欄（`key: value` / `key = value` 形式、`backup setup` / `backup reconnect` の出力貼り付けに対応）から `client_id`・`client_secret`・`refresh_token`（または `token` JSON）を読み取ります。3 項目すべてが揃っていれば `~/.config/rclone/rclone.conf`（権限 `0600`）を無操作で自動生成します。
3. **不足・失敗時の対話フォールバック**
   - Bitwarden 側に一部の項目しか無い場合は取得できた値を既定値（`[Enter で維持]`）として残りの項目だけ入力でき、`refresh_token` を空 Enter にすると対話式ブラウザ OAuth（`rclone config reconnect gdrive:`）へ進みます。
   - `rclone about gdrive:` の接続確認に失敗した場合は `[b]Bitwarden (rbw) を同期して再読込 / [r]値を手動入力 / [o]OAuth ブラウザ再接続 / [t]再試行 / [q]中止`、パスワード取得に失敗／不一致の場合は `[b]Bitwarden (rbw) を同期して再試行 / [m]パスワードを手動入力（非表示） / [q]中止` からそのままやり直せます。

固定値（リモート名 `gdrive`、`type = drive`、`scope = drive`、既定リポジトリ `rclone:gdrive:restic/<host>-home`）の入力は不要です。取得・入力した OAuth 設定は `$RCLONE_CONFIG`（既定 `~/.config/rclone/rclone.conf`、権限 `0600`）へ保存されるため、ビルド後の `backup` でもそのまま再利用できます。

`RCLONE_CONFIG`（または既存の `~/.config/rclone/rclone.conf` / `~/.rclone.conf`）に有効な `gdrive:` がある場合や、`RESTIC_PASSWORD` / `RESTIC_PASSWORD_FILE` / `RESTIC_PASSWORD_COMMAND` が設定済みの場合はそちらを優先してプロンプトを省略します。復元には**元の暗号化パスワード**が必要です。新しい鍵の生成や `backup setup` は行わないでください。

メッセージ・プロンプトは日本語で表示されます（GUI 端末・LXQt・Sway 上での利用を想定。非 CJK TTY コンソールでは表示できない文字があります）。最新スナップショットを固定し、必要容量と空き容量を確認してから、`restic restore --verify` で検証後に次のとおり復元します（検証が失敗した場合は元のファイルを変更せず一時展開先を保持して終了します）。

- **既定（`EXTRACT_DIR` なし）**: `/home/mitac` と同一ファイルシステム上の一時領域（`/var/tmp` が同一 FS なら `/var/tmp/restore-mitac-XXXXXXXX`、`/home/mitac` が別パーティションまたは Btrfs 別サブボリュームなら `/home/mitac/.restore-mitac-XXXXXXXX`）で検証後、進捗を表示しながら**元の位置へ高速に反映**し、成功時に一時ディレクトリを削除します（`復元と検証が完了しました。` を表示）。
  - ホーム: `/home/mitac/`（`~/MySettings`・`/home/mitac/Documents/hiragino-otf/` を含む。今回の実行中に Bitwarden 反映・手動入力・OAuth 再接続で新規取得／更新した `$RCLONE_CONFIG` は保持）
  - システム状態（空でないディレクトリのみ自動で `sudo` 実行）: `/etc/NetworkManager/system-connections`（ファイル権限 `0600`）・`/var/lib/bluetooth`・`/var/lib/cloudflare-warp`・`/var/lib/tailscale`（`root:root` 所有に変更し、稼働中のサービス／`nmcli` を再読み込み）
- **`--from HOST` / `--repo REPO`（リポジトリ指定）**: 別のホスト用リポジトリ（`rclone:gdrive:restic/<HOST>-home`）やローカルコピーしたリポジトリ URI を指定します。未指定時は環境変数 `RESTIC_REPOSITORY`、次に `RESTORE_HOST`／現在ホスト名に基づく `<host>-home`（`nixos` / `localhost` の場合は `mitac-home`）を使います。
- **`--new-device`（複数端末の同時運用・初期化後クリーン構築向け）**: 同一アカウント内の別端末や再インストール後の環境で衝突・競合が起きないよう、次の処理を行います：
  - **保持**: SSH 鍵（`.ssh`）・GNOME Keyring・`gh` 認証・個人データ・エディタ/IME 設定・ブラウザのブックマーク/ノート・Wi-Fi パスワード（`.nmconnection` から `interface-name=` / `mac-address=` を自動除去して別 NIC でも接続可能化）、および現在の **`~/MySettings`（既存チェックアウト・新規生成済み `hardware-configuration.nix`）**・**`rbw`（端末別 `device_id`）**・**`$RCLONE_CONFIG`**
  - **初期化（新端末で初回サインイン）**: `tailscale` / `cloudflare-warp` / `bluetooth` 状態、UniClipboard・Lan Mouse 鍵・LocalSend・RQuickShare・Parsec 端末認証、Vivaldi Sync / Cookie / アカウント状態（`Bookmarks` 等は保持）、Cursor 認証/秘密情報/テレメトリ ID（`User/settings.json` 等は保持）、Codex / ChatGPT・Grok Bot・Discord・Steam・AGY/OpenCode インストール ID 等のトークン系ログイン状態、`SingletonLock`
- **引数 `[EXTRACT_DIR]` 指定時**: `/home`・`/etc`・`/var/lib` には一切触れず、`EXTRACT_DIR`（`home/mitac/`・`run/restic-backups-home/system/`・`.restored-snapshot-id`）へ展開と検証のみを行います（`--new-device` 併用時はそのステージ領域内で初期化済み状態を検査できます）。

バックアップ対象には `~/MySettings`（`.git` や未コミットの作業を含む）も含まれますが、再生成可能な大容量キャッシュ／ゲーム本体（Steam `common` 等）および `/etc/shadow` は含まれません。ヒラギノ（`/home/mitac/Documents/hiragino-otf`）が復元された場合は、直後の OS ビルドで `--impure`（`rebuild` 導入後は自動付与）を指定してください（未配置時の既定は Noto CJK）。使い方は `./scripts/restore-on-nixos.sh --help` でも確認できます。

### 復元・確認（適用済みの環境）

このモジュールはセットアップ、systemd ユニット、rclone 確認、および restic（リポジトリ／Bitwarden パスワードコマンド設定済み）をまとめて扱う `backup` CLI を導入します（`restic-home-setup` も `backup setup` のエイリアスとして利用できます）。

すべてのファイルを元の位置へ一括復元する場合は `cd ~/MySettings && ./scripts/restore-on-nixos.sh`（別端末からは `--from <host> --new-device`）を実行します。一部ファイルだけ別ディレクトリへ取り出して確認・手動反映する場合は `backup restore latest --target /tmp/restore` を使います。他ホストのリポジトリを `backup` CLI から確認したい場合は `RESTIC_REPOSITORY=rclone:gdrive:restic/chromebook-home backup snapshots` のように環境変数で指定できます。

```bash
backup                 # 使い方
backup setup
backup run && backup log
backup snapshots
backup restore latest --target /tmp/restore
```

`--target /tmp/restore` で抽出した場合、システム状態は `/tmp/restore/run/restic-backups-home/system/` 配下に展開されます。

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
rclone copy gdrive:restic/chromebook-home /var/tmp/restic-chromebook-home \
  --fast-list --transfers 4 --checkers 8 --tpslimit 8 --drive-chunk-size 64M
./scripts/restore-on-nixos.sh --repo /var/tmp/restic-chromebook-home --new-device
# または部分抽出:
restic restore latest \
  --repo /var/tmp/restic-chromebook-home \
  --password-command 'rbw get restic-home' \
  --target /tmp/restore
```

### 注意事項

- **`restic-home-password.age` / `rclone-conf.age` が有効な環境（推奨）**: `restic-backups-home.timer` および `backup` コマンドは `/run/agenix/` の復号済み秘密情報を使って動作するため、`rbw` がロックされていても日次バックアップが無監視で成功します（手動再認証後のみ `secrets import-rclone` + `rebuild` で `/run/agenix/rclone-conf` を更新してください）。
- **agenix 未移行環境（フォールバック）**: `rbw` がロック解除済み／到達可能である必要があります。グラフィカルセッション内で `rbw-agent` をアンロック状態に保つか、セッションがない環境では先に `backup unlock-key` でアンロックしてから `backup run` を実行してください（タイマー実行時はセッションの D-Bus / Wayland 等を取り込んで `pinentry-qt` で入力を促します）。
- root のみ読める領域（Wi-Fi、Bluetooth、Cloudflare WARP、Tailscale）は root 権限の `ExecStartPre` で `/run/restic-backups-home/system/…` へ一時コピーされ、停止時に削除されます。`/etc/shadow`（ログインパスワード）は**バックアップされません**。`~/MySettings`（`.git` や未コミットの作業を含む flake チェックアウト一式）は `/home/mitac` の他のファイルと**一緒に含まれ**、同一端末向けの `./scripts/restore-on-nixos.sh` では `~/MySettings` へそのまま上書き復元されますが、`--new-device` 指定時かつ既存の `~/MySettings`（`.git` または `hosts/`）がある場合はそちら（新規生成した `hardware-configuration.nix` 等）を保持して上書きしません（`backup restore … --target /tmp/restore` 時は `/tmp/restore/home/mitac/MySettings`）。
- 再生成可能な大容量データは除外されます（Steam クライアント／ランタイムとゲーム本体 ※ `userdata` / `compatdata` のセーブデータは保持、Cursor の agent-worker バイナリとキャッシュ、Vivaldi のキャッシュ／WebStorage、Firefox の `storage`）。Vivaldi の `Default/Extensions` は Preferences のインストール記録と対になるため**含めます**（除外すると復元後に拡張が壊れる）。
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
| Flake ターゲット | `.#vaio`（`hosts/vaio/default.nix`。ホスト名 `vaio` / バックアップ先 `vaio-home`） |
| CPU / GPU | Intel 第8世代以降（Core i / Core Ultra iGPU）。`intel-media-driver` + `LIBVA_DRIVER_NAME=iHD` + `sof-firmware`（`modules/nixos/laptop/graphics.nix`） |
| オーディオ | **PipeWire + WirePlumber**（ALSA / 32bit ALSA / `pipewire-pulse` / JACK 互換）+ Bluetooth（`modules/nixos/vaio/audio.nix`）。Chromebook 用の PulseAudio / `hw:0,0` 固定・`max98373` ミキサは不使用 |
| キーボード・OOM | `keyd` により **Ctrl+Alt+Del**（**Ctrl+Alt+Backspace** も可）で手動 OOM killer（SysRq-f）＋ libinput 内部キーボード扱い。Chromebook 用 `cros` 最上段変換は適用しないため、`F1`–`F12` は通常のファンクションキーとして動作（`modules/nixos/laptop/input.nix`） |
| 電源・コード | `zram`（100% / zstd）・`thermald`・`auto-cpufreq`・`power-chords`（全 `"Power Button"` ACPI ノードを監視: 短押し=suspend / 長押し≈2.5s=poweroff / **電源+F1=強制ログアウト** / **電源+F2=再起動**）。Ice Lake eDP は `i915.enable_psr=0`（PSR2 の flip 張り付き＝偽 iowait 回避）。Chromebook 専用 `/dev/cros_ec` Type-C 制御はロードしない |
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
| Flake ターゲット | `.#chromebook`（`hosts/chromebook/default.nix`。後方互換エイリアス `.#mitac` も同一。ホスト名 `chromebook` / バックアップ先 `chromebook-home`） |
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
secrets/                          # agenix 暗号化ファイル（*.age）、公開鍵（*.pub / master-pubkey.txt）、agenix-rules.nix
hosts/chromebook/                 # delbin Chromebook エントリ + hardware-configuration.nix
hosts/vaio/                       # VAIO エントリ + hardware-configuration.nix（要実機生成）
modules/nixos/common.nix          # locale、ユーザー、Meltype/Fcitx5、フォント
modules/nixos/secrets.nix         # agenix 複号設定、nm-agenix-profiles、Tailscale authKeyFile
modules/nixos/remote-builder.nix  # wsl-builder リモートビルダー設定（agenix / ~/.ssh フォールバック）
modules/nixos/desktop.nix         # sway + greetd + console-gui + portals + XKB/印刷
modules/nixos/sway.nix            # Sway システム側（greetd 既定セッション等）
modules/nixos/greetd.nix          # tuigreet（Sway のみ）
modules/nixos/console-gui.nix     # gui / apps（Sway ランチャー等）
modules/nixos/laptop.nix          # ノート PC 共通ハードウェア集約（./laptop/*）
modules/nixos/laptop/             # graphics（Intel iHD + SOF + i915.enable_psr=0）/ input（keyd OOM）/ power（zram + thermald + auto-cpufreq + power-chords）
modules/nixos/vaio.nix            # VAIO 固有集約（./vaio/*）
modules/nixos/vaio/               # audio（PipeWire + WirePlumber + Bluetooth）
modules/nixos/chromebook.nix      # delbin Chromebook 固有集約（./chromebook/*）
modules/nixos/chromebook/         # audio（PulseAudio + UCM）/ power（Type-C EC）/ input（cros keyd + Flip）
modules/nixos/backup.nix          # 暗号化 /home → Google Drive バックアップ（agenix / restic / rclone / rbw）
modules/nixos/release.nix         # system.nixos.tags（世代ラベルのスラッグ）
home/mitac.nix                    # HM エントリ（identity + imports）
home/secrets.nix                  # agenix ユーザーシークレット連携（~/.ssh / ~/.config/gh / user-env）
home/flake-tools.nix              # repoPath / flakeHost / scripts（secrets・flake-update・waybar 等）
home/shell.nix                    # bash エイリアス / rebuild / audio-panic / runbtop
home/programs.nix                 # git / rbw / neovim / mime / 起動音 / 共通パッケージ
home/lazy-plugins.nix             # nixpkgs 由来 LazyVim プラグイン + treesitter パーサ
home/clipboard.nix                # cliphist + clipboard-history
home/sway.nix                     # Sway（waybar/mako/swayidle・rofi・jp・チートシート）
home/nvim/
scripts/secrets-tool.sh           # secrets CLI（init / bootstrap / import / edit / rekey / check）
scripts/restore-on-nixos.sh       # 実機復元（--from / --new-device / --agenix-only）
```
