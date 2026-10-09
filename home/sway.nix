# Sway Home Manager: primary desktop — waybar / mako / swayidle.
# Visual language stays terminal/greeter-adjacent (dark + cyan).
# Launcher: rofi (drun). Keyboard layout: jp.
{
  pkgs,
  lib,
  ...
}:

let
  ghosttyBin = "${pkgs.ghostty}/bin/ghostty";
  swaylockBin = "${pkgs.swaylock}/bin/swaylock";
  swayidleBin = "${pkgs.swayidle}/bin/swayidle";
  rofiBin = "${pkgs.rofi}/bin/rofi";
  yaziBin = "${pkgs.yazi}/bin/yazi";
  polkitAgent = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1";
  pactl = "${pkgs.pulseaudio}/bin/pactl";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  btopBin = "${pkgs.btop}/bin/btop";
  nmtuiBin = "${pkgs.networkmanager}/bin/nmtui";
  grim = "${pkgs.grim}/bin/grim";
  slurp = "${pkgs.slurp}/bin/slurp";
  wlCopy = "${pkgs.wl-clipboard}/bin/wl-copy";
  # Manual / before-sleep lock (always runs).
  lockCmd = "${swaylockBin} -f -c 0b0f14";
  # Presentation marker toggled with waybar scr / scr ON. XDG_RUNTIME_DIR is
  # session-scoped, so it clears on logout. Idle auto-lock / DPMS no-op while set.
  idleLockCmd = pkgs.writeShellScript "sway-idle-lock" ''
    if [ -e "''${XDG_RUNTIME_DIR}/sway-keep-screen-on" ]; then
      exit 0
    fi
    exec ${swaylockBin} -f -c 0b0f14
  '';
  idleDpmsOffCmd = pkgs.writeShellScript "sway-idle-dpms-off" ''
    if [ -e "''${XDG_RUNTIME_DIR}/sway-keep-screen-on" ]; then
      exit 0
    fi
    exec swaymsg "output * power off"
  '';
  toggleKeepScreenOn = pkgs.writeShellScript "sway-toggle-keep-screen-on" ''
    marker="''${XDG_RUNTIME_DIR}/sway-keep-screen-on"
    if [ -e "$marker" ]; then
      rm -f "$marker"
    else
      touch "$marker"
    fi
  '';
  waybarKeepScreenOn = pkgs.writeShellScript "waybar-keep-screen-on" ''
    marker="''${XDG_RUNTIME_DIR}/sway-keep-screen-on"
    if [ -e "$marker" ]; then
      printf '%s\n' '{"text":"scr ON","class":"activated","tooltip":"画面常時オン（ロック・消灯なし／クリックで解除）"}'
    else
      printf '%s\n' '{"text":"scr","class":"deactivated","tooltip":"画面を常時オンにする（ロック・消灯を抑制）"}'
    fi
  '';
  # Route launches through swaymsg exec so new windows land on the
  # workspace active at selection time (not wherever focus is when they map).
  rofiLauncher = "${rofiBin} -show drun -run-command \"swaymsg exec -- {cmd}\" -run-shell-command \"swaymsg exec -- {terminal} -e {cmd}\"";
  # waybar cpu / mem → Ghostty + btop; network → Ghostty + nmtui
  openBtop = "${ghosttyBin} -e ${btopBin}";
  openNmtui = "${ghosttyBin} -e ${nmtuiBin}";
  openYazi = "${ghosttyBin} -e ${yaziBin}";

  # Boxed reference opened floating via Ghostty + bat (selectable / copyable).
  cheatsheetText = pkgs.writeText "sway-cheatsheet.txt" ''
    Sway チートシート

    q / Esc で閉じる・ホイールで移動 / Shift+ドラッグで選択

    ┌─ 起動・終了 ─────────────────────────────────────────────┐
    │ Super+Return       Ghostty を起動                        │
    │ Ctrl+Alt+T         Ghostty を起動                        │
    │ Super+D / Alt+Space  rofi（選択時WSに起動・drun）        │
    │ Super+q            フォーカス中のウィンドウを閉じる      │
    │ Super+Shift+q      ELECOMだと Win+Shift が欠けること有   │
    │ Super+L            画面ロック（swaylock）                │
    │ Super+Shift+c      Sway 設定を再読み込み                 │
    │ Super+Shift+e      Sway を終了                           │
    └──────────────────────────────────────────────────────────┘

    ┌─ ウィンドウ ─────────────────────────────────────────────┐
    │ Super+h/j/k        フォーカス（左/下/上）                │
    │ Super+Left/…       フォーカス（矢印でも可。右は Right）  │
    │ Super+Shift+hjk…   ウィンドウを移動                      │
    │ Super+f            フルスクリーン                        │
    │ Super+r            リサイズモード（hjkl / Esc で終了）   │
    │ Super+Shift+Space  フローティング切替                    │
    │ Super+b / Super+v  水平 / 垂直分割                       │
    │ Super+s/w          スタック / タブ（分割は Super+b/v）   │
    └──────────────────────────────────────────────────────────┘
    注: Super+L=ロック、Super+e=Yazi。右は Super+Right。
    注: 既定の Super+e（分割レイアウト）は Yazi に上書き。

    ┌─ ワークスペース ─────────────────────────────────────────┐
    │ Super+1 … 9        ワークスペースへ切替                  │
    │ Super+Shift+1…9    ウィンドウを WS へ移動                │
    │ 起動時             WS1 Cursor+ChatGPT / WS2 Vivaldi      │
    └──────────────────────────────────────────────────────────┘

    ┌─ 自作バインド ───────────────────────────────────────────┐
    │ Super+e            Yazi（Ghostty 内ファイラー）          │
    │ Super+V            履歴選択→貼り付け（cliphist+rofi）    │
    │ Print              全画面スクショ → クリップボード       │
    │ Super+Shift+s      範囲スクショ（slurp）→ クリップボード │
    │ 音量キー           上げ / 下げ / ミュート                │
    │ MicMute            マイクミュート                        │
    │ 輝度キー           画面輝度 ±5%                          │
    │ Super+/            このチートシートを開閉（Shiftなし）   │
    │ Super+Shift+/      同上（ELECOMは同時押し欠け有）        │
    └──────────────────────────────────────────────────────────┘

    ┌─ 入力 ───────────────────────────────────────────────────┐
    │ Super+Space        Fcitx5 / Mozc 切替（IME）             │
    │ 配列               jp（xkb_layout）                      │
    │ NumLock            起動時オン                            │
    │ 外付けKB接続時     内蔵ATキーボードを自動無効            │
    │ systemctl start chromebook-internal-kb-guard  手動再評価 │
    │ cat /sys/class/input/input0/inhibited  0=有効 / 1=無効   │
    │ ELECOM Fn+Q / Fn+W Windows / Mac モード（Scroll点滅1/2） │
    │   Macのままだと Ctrl↔Win が入れ替わりショートカット死   │
    │ ELECOM Win+Shift   同時押しが欠けること有 → Super+q 等  │
    └──────────────────────────────────────────────────────────┘

    ┌─ Yazi（Super+e） ────────────────────────────────────────┐
    │ .                  隠しファイル表示トグル                │
    │ Tab                spot（MIME / メタ情報）               │
    │ o / Enter          開く（既定エディタは nvim）           │
    │ ; / :              シェルコマンド（非阻塞 / 阻塞）       │
    │ m+p / m+o / m+m    行モード: 権限 / 所有者 / 更新時刻    │
    │ f                  フィルタ / z → zoxide 等              │
    │ y（bash）          起動→終了後そのディレクトリへ cd      │
    └──────────────────────────────────────────────────────────┘

    ┌─ 便利ツール ─────────────────────────────────────────────┐
    │ showmethekey       キー押下オーバーレイ（rofi から起動） │
    │ LocalSend          LAN ファイル送受信（rofi から）       │
    │ bcat               bat（シンタックスハイライト付き cat） │
    │ waybar [restic]    バックアップ実行中の進捗表示          │
    │ waybar ?           このチートシート（再押下で閉じる）    │
    │ 無操作 10分→ロック / 15分→画面オフ（suspend しない）     │
    │ waybar scr / scr ON  常時オン（自動ロック・消灯を抑制）  │
    │ waybar net / bri   SSID（ホバーで↓↑速度） / 画面輝度     │
    │ waybar cpu/mem クリックで btop / net で nmtui（Ghostty） │
    │ gh auth login      GitHub 認証（初回・期限切れ時）       │
    │ git push           HTTPS は gh 資格情報を自動使用        │
    └──────────────────────────────────────────────────────────┘

    ┌─ Cursor CLI（agent） ────────────────────────────────────┐
    │ agent              対話セッション開始                    │
    │ agent "…"          プロンプト付きで開始                  │
    │ agent login        認証（初回）                          │
    │ /ask /plan         読取専用 / 計画モード（Shift+Tab）    │
    │ agent ls / resume  過去セッション一覧 / 再開             │
    │ agent -p "…"       非対話（スクリプト向け）              │
    │ @ファイル          コンテキストに追加                    │
    └──────────────────────────────────────────────────────────┘

    ┌─ AI（GUI・rofi から起動） ───────────────────────────────┐
    │ ChatGPT            公式デスクトップ（Codex 含む）        │
    │ DeepSeek Harness   アプリ窓（初回は npm、:3080）         │
    └──────────────────────────────────────────────────────────┘

    ┌─ Neovim（LazyVim） ──────────────────────────────────────┐
    │ Space              リーダー（どのキーマップもここから）  │
    │ Space e            エクスプローラー                      │
    │ Space ff / Space sg  ファイル検索 / 全文検索（rg）       │
    │ Space l            Lazy プラグイン UI                    │
    │ Space cf           フォーマット                          │
    │ gd / gr / K        定義へ / 参照 / ホバー                │
    │ :Lazy sync         プラグイン更新（初回インストールも）  │
    └──────────────────────────────────────────────────────────┘
    初回はネット必須。LSP は Mason ではなく nix extraPackages。

    ┌─ NixOS 適用 ─────────────────────────────────────────────┐
    │ flake-update       入力一括＋Cursor/SendAnywhere/UniClip │
    │ nix flake update   入力のみ（UniClip の版は動かない）    │
    │ rebuild            sudo後・適用（ビルド中のみ nom ETA）  │
    │ generations        世代一覧（list-generations）          │
    │ 更新で壊れたとき   sudo nixos-rebuild --rollback switch  │
    │                    または git checkout <良コミット> --   │
    │                    flake.lock → rebuild                  │
    │ nix-collect-garbage  未参照ストアのみ削除（世代は残る）  │
    │ sudo nix-collect-garbage -d  全世代削除+GC（危険）       │
    │ sudo nix-collect-garbage --delete-older-than 30d         │
    │                    30日より古い世代だけ削除してから GC   │
    │ nix store optimise 重複パスをハードリンクして容量節約    │
    └──────────────────────────────────────────────────────────┘

    ┌─ リモートビルド（galleria-mitac WSL :2222） ─────────────┐
    │ 鍵                 ~/.ssh/id_wsl_builder（パス無し）     │
    │ 疎通（ユーザー）   ssh wsl-builder nix --version         │
    │ 疎通（daemon）     sudo ssh wsl-builder nix --version    │
    │ 強制リモート       --max-jobs 0（ローカルを使わない）    │
    │ リモート無効       --builders ''''（空文字）             │
    │ 向こうでビルド→持込  nix copy --from ssh://wsl-builder … │
    └──────────────────────────────────────────────────────────┘

    ┌─ VM（libvirt / QEMU/KVM） ───────────────────────────────┐
    │ virt-manager       GUI（qemu:///system）                 │
    │ virsh list --all   VM 一覧                               │
    │ virsh net-list --all  仮想ネットワーク一覧               │
    │ virsh net-start default  初回: NAT (virbr0) を起動       │
    │ virsh net-autostart default  起動時に default を有効     │
    │ virt-viewer NAME   ゲスト画面だけ開く                    │
    │ ls /dev/kvm        あればハードウェア仮想化 OK           │
    └──────────────────────────────────────────────────────────┘
    グループ変更後は一度ログアウト／再ログイン。

    ┌─ バックアップ（restic → Google Drive） ──────────────────┐
    │ 事前               rbw unlock（鍵が必要）                │
    │ 手動実行           sudo systemctl start                  │
    │                    restic-backups-home.service           │
    │ 進捗ログ           journalctl -u restic-backups-home -f  │
    │ backup snapshots   スナップショット一覧                  │
    │ backup restore …   復元（必ず --target を付ける）        │
    │   例: backup restore latest --target /tmp/restore        │
    │ 初回セットアップ   restic-home-setup                     │
    └──────────────────────────────────────────────────────────┘
    注: --target なしは /home/mitac を直接上書きするので危険。
    展開先は /tmp/restore/home/mitac/... になる。

    ┌─ Lan Mouse（Windows のマウス／KB を受信） ───────────────┐
    │ lan-mouse          GUI（Authorize / 設定）               │
    │ daemon 停止        systemctl --user stop lan-mouse       │
    │ daemon 再開        systemctl --user start lan-mouse      │
    │ Windows            winget install lan-mouse → GUI で Add │
    │ ポート             UDP 4242（同一 LAN / Tailscale）      │
    └──────────────────────────────────────────────────────────┘
    GUI 前に daemon が占有しているときは一度 stop してから開く。

    ┌─ UniClipboard（Windows と CB 同期） ─────────────────────┐
    │ GUI                uniclipboard                          │
    │ daemon 状態        systemctl --user status uniclipd      │
    │ daemon 再起動      systemctl --user restart uniclipd     │
    │ ログ               journalctl --user -u uniclipd -f     │
    │ 詳細ログ           ~/.local/state/.../uniclipboard/logs  │
    │ 鍵環ロック時       seahorse（Default Keyring を解錠）    │
    │ ピア拒否           Devices→相手→「この端末と同期」ON    │
    │                    （tray Device Sync のチェックでも可） │
    └──────────────────────────────────────────────────────────┘
    必ず --user。daemon 再起動後は GUI も落として開き直す
    （旧ポートに張り付いて接続できなくなる）。
    起動失敗(engine 1223)は鍵環未解錠が典型。seahorse で解錠。
    「ピア拒否」は受信オフ時の正常動作。both/receive に設定。
    アプリ内 Update は触らない（deb 導入で daemon が止まる）。
    版上げは flake の pkgs.uniclipboard で行う。

    ┌─ Cloudflare WARP ────────────────────────────────────────┐
    │ warp-cli status    接続状態                              │
    │ warp-cli connect   接続                                  │
    │ warp-cli disconnect 切断                                 │
    │ warp-taskbar       トレイ GUI                            │
    └──────────────────────────────────────────────────────────┘

    ┌─ Chromebook 最上段キー ──────────────────────────────────┐
    │ 単体               Back/Refresh/全画面/輝度/音量 など    │
    │ Search+最上段      F1–F10                                │
    │ Search+3つ目       tuigreet セッション一覧（F3）         │
    │ Ctrl+Alt+Del       手動 OOM killer（画面固まり時用）     │
    │                    （内蔵KBは Ctrl+Alt+Backspace）       │
    │ 電源 短押し        suspend                               │
    │ 電源 長押し(~2.5s) poweroff                              │
    │ 電源+Back          強制ログアウト                        │
    │ 電源+Refresh       再起動                                │
    └──────────────────────────────────────────────────────────┘

    ┌─ USB-C 電力ロール ───────────────────────────────────────┐
    │ 空きポートは受電優先 / スマホ検出時・AC時は他ポート給電 │
    │ sudo chromebook-typec-prefer-sink   ポリシー再適用      │
    │ 充電できない(緊急): 抜く → mask → FORCE_SINK → 挿す    │
    │   sudo systemctl mask --runtime \                       │
    │     chromebook-typec-prefer-sink.service                │
    │ cat /sys/class/typec/port*/power_role  (sink=受電)      │
    └──────────────────────────────────────────────────────────┘

    ┌─ バッテリー節約（都度） ─────────────────────────────────┐
    │ 輝度キー / brightnessctl set 40%   画面が最大の消費源   │
    │ warp-cli disconnect          不要なら WARP 切断         │
    │ bluetoothctl power off       未使用時 BT オフ           │
    │ 電源短押し / systemctl suspend   離席時は suspend       │
    │ ※idle は 10分ロック / 15分画面オフのみ（自動 suspend 無）│
    └──────────────────────────────────────────────────────────┘

    ┌─ ESP32 / Arduino CLI ────────────────────────────────────┐
    │ ポート: /dev/ttyUSB0（CH340）。安定名:                   │
    │   /dev/serial/by-id/usb-1a86_USB_Serial-if00-port0     │
    │ esptool --port /dev/ttyUSB0 chip-id                    │
    │ arduino-cli board list                                 │
    │ arduino-cli core update-index                          │
    │ arduino-cli core install esp32:esp32                   │
    │ arduino-cli compile -b esp32:esp32:esp32 .             │
    │ arduino-cli upload -p /dev/ttyUSB0 -b esp32:esp32:esp32. │
    │ ※シリアルは dialout 必須（rebuild 後に再ログイン）       │
    └──────────────────────────────────────────────────────────┘

    ┌─ Android（QtScrcpy / adb） ──────────────────────────────┐
    │ QtScrcpy           画面ミラー＋操作（アプリメニュー可） │
    │ adb devices        USB/無線で認識中の端末               │
    │ ※端末側で USB デバッグ ON。初回は許可ダイアログ承認     │
    └──────────────────────────────────────────────────────────┘

    ┌─ Network（IP 確認 / 自宅はルータ DHCP 予約） ────────────┐
    │ nmtui              TUI で Wi-Fi/有線の接続設定           │
    │                    （waybar の SSID クリックでも開く）   │
    │ ip -br addr        全 IF の IP（LAN/Tailscale/WARP）     │
    │ ip route           デフォルト GW（dhcp / static）        │
    │ nmcli -f IP4 device show wlp0s20f3   Wi-Fi IP/GW/DNS   │
    │ cat /sys/class/net/wlp0s20f3/address   Wi-Fi MAC        │
    │ ※接続時 MAC は固定（cloned-mac=preserve）。予約に使う    │
    │ iperf3 -s          帯域測定サーバ（TCP/UDP 5201）        │
    │ iperf3 -c HOST     クライアント（サーバ側 IP を指定）    │
    │ iperf3 -c HOST -R  下り方向も測る（reverse）             │
    └──────────────────────────────────────────────────────────┘

    ┌─ メモリ / OOM ───────────────────────────────────────────┐
    │ Ctrl+Alt+Del       手動 OOM（内蔵は C-A-Backspace）      │
    │ free -h / swapon --show   RAM・zram 使用量              │
    │ journalctl -k -b | rg -i 'Out of memory|oom-kill'       │
    │ journalctl -u systemd-oomd -b   userspace OOM の有無     │
    │ waybar cpu/mem クリック → btop                          │
    └──────────────────────────────────────────────────────────┘

    ┌─ Bluetooth（bluetoothctl） ──────────────────────────────┐
    │ bluetoothctl       対話モードを開始                      │
    │   power on         電源オン                              │
    │   agent on         エージェント有効                      │
    │   default-agent    既定エージェント                      │
    │   scan on          スキャン開始                          │
    │   pair MAC         ペアリング                            │
    │   trust MAC        信頼                                  │
    │   connect MAC      接続                                  │
    │   scan off / quit  終了                                  │
    │ devices / info MAC 一覧・詳細                            │
    └──────────────────────────────────────────────────────────┘
    音声デバイスは接続後、Pulse 側で出力シンクを選ぶことあり。
  '';

  # Esc → quit (q still works). Lone Esc after less's timeout; arrows stay intact.
  cheatsheetLesskey = pkgs.writeText "sway-cheatsheet.lesskey" ''
    #command
    q quit
    Q quit
    \e quit
  '';

  # Custom syntax so keys / section headers are colored (plain .txt has none).
  cheatsheetSyntax = pkgs.writeText "SwayCheatsheet.sublime-syntax" ''
    %YAML 1.2
    ---
    name: SwayCheatsheet
    file_extensions: [swaycheat]
    scope: text.swaycheatsheet
    contexts:
      main:
        - match: '^Sway .+$'
          scope: markup.heading.1
        - match: '^q / Esc.+$'
          scope: comment.line
        - match: '^注:.+$'
          scope: markup.italic
        - match: '^┌─.+┐$'
          scope: markup.heading.2
        - match: '^└─.+┘$'
          scope: punctuation.section
        - match: '^(※|必ず|起動失敗|「|アプリ内|版上げ|グループ|GUI |音声|展開先|初回は).*$'
          scope: comment.line
        - match: '^│'
          push:
            - match: '│$'
              scope: punctuation.section
              pop: true
            - match: '[│]'
              scope: punctuation.section
            - match: '  +\S.*(?=│$)'
              scope: string.unquoted
            - match: '\S+'
              scope: entity.name.function
  '';

  # Prebuilt bat cache (syntaxes.bin) so runtime needs no writable ~/.cache.
  cheatsheetBatHome = pkgs.runCommand "sway-cheatsheet-bat-home" { nativeBuildInputs = [ pkgs.bat ]; } ''
    mkdir -p $out/config/syntaxes $out/cache
    cp ${cheatsheetSyntax} $out/config/syntaxes/SwayCheatsheet.sublime-syntax
    export BAT_CONFIG_DIR=$out/config
    export XDG_CACHE_HOME=$out/cache
    bat cache --build
  '';

  # Single argv for ghostty -e (multi-arg -e is easy to break; breaks keys/pager).
  cheatsheetViewer = pkgs.writeShellScript "sway-cheatsheet-view" ''
    set -eu
    export PATH="${lib.makeBinPath [ pkgs.bat pkgs.less pkgs.coreutils ]}:$PATH"
    export BAT_CONFIG_DIR="${cheatsheetBatHome}/config"
    export XDG_CACHE_HOME="${cheatsheetBatHome}/cache"
    export LESS='-R'
    # Coldark-Cold is a light theme (fg≈234 → invisible on dark Ghostty).
    # Pipe to less ourselves: --mouse for wheel scroll; Shift+drag still selects in Ghostty.
    bat --style=plain --paging=never --color=always --wrap=never \
      --theme=OneHalfDark -l SwayCheatsheet \
      ${cheatsheetText} \
      | exec less -R --mouse --wheel-lines=3 --lesskey-src=${cheatsheetLesskey}
  '';

  showCheatsheet = pkgs.writeShellScript "sway-cheatsheet" ''
    set -eu
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.jq
        pkgs.procps
        pkgs.sway
        pkgs.ghostty
      ]
    }:$PATH"
    # Toggle: second ? / Super+/ closes an existing sheet.
    # swaymsg kill is a no-op for this Ghostty+-e window; terminate its PID instead.
    mapfile -t pids < <(
      swaymsg -t get_tree \
        | jq -r '.. | objects | select(.app_id? == "com.mitac.SwayCheatsheet") | .pid' \
        | sort -u
    )
    if ((''${#pids[@]} > 0)); then
      kill "''${pids[@]}" 2>/dev/null || true
      exit 0
    fi
    # Ghostty requires a valid GTK app-id (reverse-DNS); hyphens-only ids are ignored.
    # Options use --key=value (no -o); needed so single-instance Ghostty doesn't swallow this.
    # CJK monospace fallback keeps box columns aligned with ASCII.
    exec ghostty --class=com.mitac.SwayCheatsheet \
      --gtk-single-instance=false \
      --font-family="JetBrainsMono Nerd Font" \
      --font-family="Noto Sans Mono CJK JP" \
      --window-padding-x=8 \
      --window-padding-y=8 \
      -e ${cheatsheetViewer}
  '';
in
{
  wayland.windowManager.sway = {
    enable = true;
    package = null; # use system programs.sway
    wrapperFeatures.gtk = true;
    checkConfig = false;
    config = {
      modifier = "Mod4";
      terminal = ghosttyBin;
      menu = rofiLauncher;

      # Fixed autostart apps: place by criteria (ChatGPT is XWayland).
      assigns = {
        "1" = [
          { app_id = "cursor"; }
          { class = "ChatGPT"; }
        ];
        "2" = [
          { app_id = "vivaldi-stable"; }
        ];
      };

      # Dark solid backdrop + cyan accents (greeter / classic TUI vibe).
      output."*" = {
        bg = "#0b0f14 solid_color";
      };

      fonts = {
        names = [ "JetBrainsMono Nerd Font" ];
        size = 11.0;
      };

      colors = {
        focused = {
          border = "#33c5c5";
          background = "#0b0f14";
          text = "#e6edf3";
          indicator = "#33c5c5";
          childBorder = "#33c5c5";
        };
        focusedInactive = {
          border = "#3a4656";
          background = "#0b0f14";
          text = "#9aa7b5";
          indicator = "#3a4656";
          childBorder = "#3a4656";
        };
        unfocused = {
          border = "#1c2430";
          background = "#0b0f14";
          text = "#6b7785";
          indicator = "#1c2430";
          childBorder = "#1c2430";
        };
        urgent = {
          border = "#e06c75";
          background = "#0b0f14";
          text = "#e6edf3";
          indicator = "#e06c75";
          childBorder = "#e06c75";
        };
      };

      gaps = {
        inner = 4;
        outer = 4;
      };

      window = {
        border = 2;
        titlebar = false;
      };

      # Status bar is waybar (started in startup).
      bars = [ ];

      input = {
        "type:keyboard" = {
          xkb_layout = "jp";
          # Sway clears NumLock on start unless this is set.
          xkb_numlock = "enabled";
        };
        "type:touchpad" = {
          natural_scroll = "disabled";
          tap = "enabled";
          dwt = "disabled";
        };
      };

      keybindings =
        let
          mod = "Mod4";
        in
        lib.mkOptionDefault {
          # Super+D / Alt+Space → rofi. Super+F fullscreen, Super+R resize.
          # Super+Space stays IME. --inhibited: work inside Cursor/Electron.
          "${mod}+d" = null;
          "--inhibited ${mod}+d" = "exec ${rofiLauncher}";
          "--inhibited Mod1+space" = "exec ${rofiLauncher}";
          "Ctrl+Alt+t" = "exec ${ghosttyBin}";
          "${mod}+Return" = "exec ${ghosttyBin}";
          "${mod}+l" = "exec ${lockCmd}";
          # Yazi (overrides default Super+e layout toggle).
          "${mod}+e" = "exec ${openYazi}";
          # Clipboard history (cliphist store runs in startup).

          "${mod}+v" = "exec clipboard-history";
          # Volume / mic (PulseAudio on sof-rt5682 Chromebook).
          "XF86AudioRaiseVolume" = "exec ${pactl} set-sink-volume @DEFAULT_SINK@ +5%";
          "XF86AudioLowerVolume" = "exec ${pactl} set-sink-volume @DEFAULT_SINK@ -5%";
          "XF86AudioMute" = "exec ${pactl} set-sink-mute @DEFAULT_SINK@ toggle";
          "XF86AudioMicMute" = "exec ${pactl} set-source-mute @DEFAULT_SOURCE@ toggle";
          "XF86MonBrightnessUp" = "exec ${brightnessctl} set +5%";
          "XF86MonBrightnessDown" = "exec ${brightnessctl} set 5%-";
          # Screenshots.
          "Print" = "exec ${grim} - | ${wlCopy}";
          "${mod}+Shift+s" = "exec ${grim} -g \"$(${slurp})\" - | ${wlCopy}";
          # Cursor / Vivaldi / Discord inhibit compositor shortcuts while focused.
          # --inhibited keeps window-mgmt binds working inside those apps.
          # ELECOM TK-FCP097 often fails to register Win+Shift+* (matrix); prefer
          # Super+q without Shift. Keep Super+Shift+q for other keyboards.
          "${mod}+Shift+q" = null;
          "--inhibited ${mod}+q" = "kill";
          "--inhibited ${mod}+Shift+q" = "kill";
          # Floating bat cheatsheet (also waybar ?).
          # Prefer Super+/ (no Shift): same ELECOM Win+Shift ghosting issue.
          "--inhibited ${mod}+slash" = "exec ${showCheatsheet}";
          # JP emits keysym "question" for Shift+/ when Super is still held.
          "--inhibited ${mod}+question" = "exec ${showCheatsheet}";
        };

      startup = [
        { command = polkitAgent; }
        { command = "fcitx5 -d --replace"; }
        { command = "wl-paste --type text --watch cliphist store"; }
        { command = "wl-paste --type image --watch cliphist store"; }
        # Fixed session apps (assigns: WS1 cursor/ChatGPT, WS2 vivaldi).
        { command = "cursor"; }
        { command = "vivaldi"; }
        { command = "chatgpt"; }
        { command = "swaymsg 'workspace number 1'"; }
        # waybar: programs.waybar.systemd (MemoryMax / Restart)
        {
          command = ''
            ${swayidleBin} -w \
              timeout 600 '${idleLockCmd}' \
              timeout 900 '${idleDpmsOffCmd}' \
              resume 'swaymsg "output * power on"' \
              before-sleep '${lockCmd}'
          '';
        }
      ];
    };

    extraConfig = ''
      # showmethekey floating overlay
      for_window [app_id="showmethekey-gtk"] floating enable, sticky enable, border none
      for_window [app_id="one.alynx.showmethekey"] floating enable, sticky enable, border none
      # Sway cheatsheet (Ghostty + bat; selectable text). Height <1080 so title is not clipped.
      for_window [app_id="com.mitac.SwayCheatsheet"] floating enable, sticky enable, resize set 780 920, move position center
      # Layout-independent cheatsheet toggles (same as waybar ?)
      # --inhibited: work even when Cursor/Electron inhibit compositor shortcuts.
      bindsym --inhibited --to-code Mod4+slash exec ${showCheatsheet}
      bindsym --inhibited --to-code Mod4+Shift+slash exec ${showCheatsheet}
    '';
  };

  # Cap waybar so a module leak cannot OOM the whole 8 GiB session again.
  # Started via programs.waybar.systemd (sway-session → graphical-session).
  systemd.user.services.waybar = {
    Service = {
      MemoryMax = "256M";
      MemoryHigh = "192M";
      Restart = "on-failure";
      RestartSec = "2";
    };
  };

  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "bottom";
        height = 30;
        modules-left = [
          "custom/cheatsheet"
          "sway/workspaces"
          "sway/mode"
        ];
        modules-center = [ "sway/window" ];
        modules-right = [
          "custom/restic"
          "cpu"
          "memory"
          "custom/keep-screen-on"
          "battery"
          "network"
          "backlight"
          "pulseaudio"
          "clock"
          "tray"
        ];
        "custom/cheatsheet" = {
          format = "?";
          tooltip = "チートシート";
          on-click = "${showCheatsheet}";
        };
        "sway/workspaces" = {
          disable-scroll = true;
          all-outputs = true;
        };
        "sway/window" = {
          max-length = 48;
        };
        # Status file written by modules/nixos/backup.nix while restic runs.
        "custom/restic" = {
          exec = pkgs.writeShellScript "waybar-restic" ''
            f="''${XDG_RUNTIME_DIR}/restic-home-status"
            if [ -s "$f" ]; then
              cat "$f"
            else
              printf '%s\n' '{"text":"","class":"idle"}'
            fi
          '';
          return-type = "json";
          interval = 2;
          signal = 8;
          hide-empty-text = true;
          tooltip = true;
        };
        # Plasma-like "keep screen on": marker gates swayidle auto-lock / DPMS.
        # (Custom module so the label always matches the skip-lock state.)
        "custom/keep-screen-on" = {
          exec = "${waybarKeepScreenOn}";
          return-type = "json";
          interval = 1;
          on-click = "${toggleKeepScreenOn}";
        };
        cpu = {
          format = "cpu {usage}%";
          interval = 5;
          on-click = openBtop;
        };
        memory = {
          format = "mem {percentage}%";
          interval = 5;
          on-click = openBtop;
        };
        battery = {
          format = "{capacity}% {icon}";
          format-icons = [
            "batt"
            "batt"
            "batt"
            "batt"
            "batt"
          ];
          format-charging = "{capacity}% chg";
          states = {
            warning = 30;
            critical = 15;
          };
        };
        network = {
          interval = 2;
          format-wifi = "{essid}";
          format-ethernet = "{ifname}";
          format-disconnected = "offline";
          tooltip-format = "↓{bandwidthDownBytes} ↑{bandwidthUpBytes}\n{ifname} {ipaddr}";
          on-click = openNmtui;
        };
        backlight = {
          device = "intel_backlight";
          format = "bri {percent}%";
        };
        pulseaudio = {
          format = "vol {volume}%";
          format-muted = "mute";
          on-click = "${pactl} set-sink-mute @DEFAULT_SINK@ toggle";
        };
        clock = {
          format = "{:%a %m-%d %H:%M}";
          tooltip-format = "{:%Y-%m-%d %H:%M:%S}";
        };
      };
    };
    style = ''
      * {
        border: none;
        border-radius: 0;
        /* CJK fallback: JetBrains Mono alone metrics-clip Japanese in a short bar. */
        font-family: "JetBrainsMono Nerd Font", "Noto Sans CJK JP", sans-serif;
        font-size: 11px;
        min-height: 0;
      }
      window#waybar {
        background: #0b0f14;
        color: #9fe7e7;
      }
      /* Match bar chrome; do not inherit Plasma light GTK tooltips. */
      tooltip {
        background: #0b0f14;
        color: #9fe7e7;
        border: 1px solid #33c5c5;
      }
      tooltip label {
        color: #9fe7e7;
      }
      #workspaces button {
        padding: 0 6px;
        color: #6b7785;
        background: transparent;
      }
      #workspaces button.focused {
        color: #e6edf3;
        background: #15383a;
        border-bottom: 2px solid #33c5c5;
      }
      #workspaces button.urgent {
        color: #e6edf3;
        background: #3a1a1e;
      }
      #mode {
        color: #e06c75;
        padding: 0 8px;
      }
      #window {
        color: #9aa7b5;
        padding: 0 8px;
      }
      #custom-cheatsheet, #cpu, #memory, #custom-keep-screen-on, #battery, #network, #backlight, #pulseaudio, #clock, #tray {
        padding: 0 8px;
        color: #9fe7e7;
      }
      #custom-cheatsheet {
        color: #33c5c5;
      }
      #custom-keep-screen-on.activated {
        color: #e6edf3;
        background: #15383a;
        border-left: 2px solid #33c5c5;
      }
      #custom-keep-screen-on.deactivated {
        color: #6b7785;
      }
      #custom-restic {
        padding: 0 8px;
        color: #e6edf3;
        background: #15383a;
      }
      /* Left accent (not border-bottom / inset underline): those ate vertical
         space in a short bar and clipped バックアップ … glyph tops/bottoms. */
      #custom-restic.running {
        color: #9fe7e7;
        border-left: 2px solid #33c5c5;
      }
      #custom-restic.done {
        color: #98c379;
      }
      #custom-restic.failed {
        color: #e06c75;
        background: #3a1a1e;
      }
      #battery.warning { color: #e5c07b; }
      #battery.critical { color: #e06c75; }
      #network.disconnected { color: #6b7785; }
      #pulseaudio.muted { color: #6b7785; }
    '';
  };

  services.mako = {
    enable = true;
    settings = {
      font = "JetBrainsMono Nerd Font 11";
      background-color = "#0b0f14dd";
      text-color = "#e6edf3";
      border-color = "#33c5c5";
      border-size = 2;
      border-radius = 0;
      padding = 10;
      margin = 8;
      default-timeout = 8000;
      max-visible = 4;
      layer = "overlay";
    };
  };
}
