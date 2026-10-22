# Sway Home Manager: primary desktop — waybar / mako / swayidle.
# Visual language stays terminal/greeter-adjacent (dark + cyan).
# Launcher: rofi (drun). Keyboard layout: jp.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  flakeRoot = "${config.home.homeDirectory}/MySettings";
  flakeUpdateCheck = "${flakeRoot}/scripts/flake-update-check.sh";
  flakeUpdate = "${flakeRoot}/scripts/flake-update.sh";
  waybarAiStatus = "${pkgs.python3}/bin/python3 ${flakeRoot}/scripts/waybar-ai-status.py";
  ghosttyBin = "${pkgs.ghostty}/bin/ghostty";
  openFlakeUpdate = "${ghosttyBin} -e ${flakeUpdate}";
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
  # waybar cpu / mem → Ghostty + btop; network → Ghostty + nmtui; clock → time.is
  openBtop = "${ghosttyBin} -e ${btopBin}";
  openNmtui = "${ghosttyBin} -e ${nmtuiBin}";
  openYazi = "${ghosttyBin} -e ${yaziBin}";
  openTimeIs = "${pkgs.xdg-utils}/bin/xdg-open https://time.is/Tokyo";

  # Searchable / clickable cheatsheet (rofi -dmenu).
  # - keys only → notify-send (no key injection)
  # - run + mode=term → Ghostty interactive shell
  # - run + mode=exec → swaymsg exec (one-shot)
  # - run + mode=show → Ghostty shows command; does not run (dangerous)
  cheatsheetEntries = [
    # 起動・終了
    {
      section = "起動・終了";
      label = "Ghostty";
      keys = "Super+Return / Ctrl+Alt+T";
    }
    {
      section = "起動・終了";
      label = "rofi（選択中 WS に起動）";
      keys = "Super+D / Alt+Space";
    }
    {
      section = "起動・終了";
      label = "ウィンドウを閉じる";
      keys = "Super+q";
    }
    {
      section = "起動・終了";
      label = "画面ロック";
      keys = "Super+L";
    }
    {
      section = "起動・終了";
      label = "設定再読込 / Sway 終了";
      keys = "Super+Shift+c / e";
    }
    {
      section = "起動・終了";
      label = "再起動";
      run = "systemctl reboot";
      mode = "show";
    }
    {
      section = "起動・終了";
      label = "シャットダウン";
      run = "systemctl poweroff";
      mode = "show";
    }
    {
      section = "起動・終了";
      label = "このシート（waybar ?）";
      keys = "Super+/";
    }
    {
      section = "起動・終了";
      label = "注: ELECOM は Win+Shift 同時押しが欠けること有 → Super+q 等";
    }
    # ウィンドウ・WS
    {
      section = "ウィンドウ・WS";
      label = "フォーカス（右は Right）";
      keys = "Super+hjkl / 矢印";
    }
    {
      section = "ウィンドウ・WS";
      label = "ウィンドウ移動";
      keys = "Super+Shift+hjkl";
    }
    {
      section = "ウィンドウ・WS";
      label = "フルスクリーン / リサイズ";
      keys = "Super+f / r";
    }
    {
      section = "ウィンドウ・WS";
      label = "フローティング切替";
      keys = "Super+Shift+Space";
    }
    {
      section = "ウィンドウ・WS";
      label = "水平 / 垂直分割";
      keys = "Super+b / v";
    }
    {
      section = "ウィンドウ・WS";
      label = "スタック / タブ";
      keys = "Super+s / w";
    }
    {
      section = "ウィンドウ・WS";
      label = "WS 切替 / ウィンドウを移動";
      keys = "Super+1…9 / Shift+1…9";
    }
    {
      section = "ウィンドウ・WS";
      label = "WS1 Cursor+GPT / WS2 Vivaldi";
      keys = "起動時";
    }
    {
      section = "ウィンドウ・WS";
      label = "外部リンク → Vivaldi(WS2)へフォーカス";
    }
    {
      section = "ウィンドウ・WS";
      label = "注: Super+e は既定の分割ではなく Yazi";
    }
    # スクショ・音量・輝度・履歴
    {
      section = "スクショ・音量・輝度";
      label = "全画面 → クリップボード";
      keys = "Print";
    }
    {
      section = "スクショ・音量・輝度";
      label = "範囲選択 → クリップボード";
      keys = "Super+Shift+s";
    }
    {
      section = "スクショ・音量・輝度";
      label = "クリップボード履歴（rofi）";
      keys = "Super+V";
    }
    {
      section = "スクショ・音量・輝度";
      label = "± / ミュート / 輝度 ±5%";
      keys = "音量 / MicMute / 輝度キー";
    }
    # 入力・Chromebook
    {
      section = "入力・Chromebook";
      label = "IME 有効/無効（Meltype）";
      keys = "Super+Space";
    }
    {
      section = "入力・Chromebook";
      label = "Meltype 内: 英数 ⇔ 日本語";
      keys = "半角/全角";
    }
    {
      section = "入力・Chromebook";
      label = "ChatGPT で英語のまま戻らない → 再起動";
      keys = "ShareInputState + Meltype先頭";
    }
    {
      section = "入力・Chromebook";
      label = "Cursor で Meltype → 終了して開き直す";
      keys = "Wayland IME フラグ";
    }
    {
      section = "入力・Chromebook";
      label = "~/.local/share/Meltype";
      keys = "学習データ";
    }
    {
      section = "入力・Chromebook";
      label = "右クリック（Chromebook）";
      keys = "2本指タップ・押下";
    }
    {
      section = "入力・Chromebook";
      label = "F1–F10（3つ目=セッション）";
      keys = "Search+最上段";
    }
    {
      section = "入力・Chromebook";
      label = "手動 OOM（内蔵=C-A-Bksp）";
      keys = "Ctrl+Alt+Del";
    }
    {
      section = "入力・Chromebook";
      label = "suspend / poweroff";
      keys = "電源 短/長押し";
    }
    {
      section = "入力・Chromebook";
      label = "強制ログアウト / 再起動";
      keys = "電源+Back / +Refresh";
    }
    {
      section = "入力・Chromebook";
      label = "Windows / Mac モード";
      keys = "ELECOM Fn+Q / Fn+W";
    }
    {
      section = "入力・Chromebook";
      label = "注: ELECOM を Mac のままにすると Ctrl↔Win が入れ替わる";
    }
    # Yazi / Neovim
    {
      section = "Yazi / Neovim";
      label = "Yazi（Ghostty 内）";
      keys = "Super+e";
      run = yaziBin;
      mode = "term";
    }
    {
      section = "Yazi / Neovim";
      label = "隠し表示 / spot / 開く";
      keys = ". / Tab / Enter";
    }
    {
      section = "Yazi / Neovim";
      label = "特定アプリで開く";
      keys = "O";
    }
    {
      section = "Yazi / Neovim";
      label = "パス / 親dir / 名前 コピー";
      keys = "cc / cd / cf";
    }
    {
      section = "Yazi / Neovim";
      label = "シェル / フィルタ / zoxide";
      keys = "; / : / f / z";
    }
    {
      section = "Yazi / Neovim";
      label = "終了後その dir へ cd";
      keys = "y（bash）";
    }
    {
      section = "Yazi / Neovim";
      label = "nvim リーダー";
      keys = "Space";
    }
    {
      section = "Yazi / Neovim";
      label = "ツリー / ファイル / 全文検索";
      keys = "Space e / ff / sg";
    }
    {
      section = "Yazi / Neovim";
      label = "定義 / 参照 / ホバー";
      keys = "gd / gr / K";
    }
    # Waybar・日常
    {
      section = "Waybar・日常";
      label = "チートシート / 常時オン切替";
      keys = "? / scr";
    }
    {
      section = "Waybar・日常";
      label = "btop";
      keys = "cpu·mem クリック";
      run = btopBin;
      mode = "term";
    }
    {
      section = "Waybar・日常";
      label = "nmtui";
      keys = "net クリック";
      run = nmtuiBin;
      mode = "term";
    }
    {
      section = "Waybar・日常";
      label = "time.is（東京）";
      keys = "日付クリック";
      run = openTimeIs;
      mode = "exec";
    }
    {
      section = "Waybar・日常";
      label = "バックアップ進捗";
      keys = "[restic]（WS の右）";
    }
    {
      section = "Waybar・日常";
      label = "10分ロック / 15分画面オフ";
      keys = "無操作";
    }
    {
      section = "Waybar・日常";
      label = "LAN 送受信 / キー表示（rofi）";
      keys = "LocalSend / showmethekey";
    }
    {
      section = "Waybar・日常";
      label = "AI（rofi から）";
      keys = "ChatGPT / Grok";
    }
    {
      section = "Waybar・日常";
      label = "AI稼働（右バー中央・ホバーで詳細）";
      keys = "Cursor / ChatGPT / Grok / OpenCode";
    }
    {
      section = "Waybar・日常";
      label = "エージェント画面操作中（ChatGPT / Cursorブラウザ）";
      keys = "青枠＋バナー＋チャット";
    }
    {
      section = "Waybar・日常";
      label = "画面操作を停止";
      keys = "Esc / Super+Esc / 停止";
      run = "agent-screen-stop";
      mode = "exec";
    }
    # Cursor 進捗（他アプリ使用中）
    {
      section = "Cursor 進捗";
      label = "完了・入力待ち → mako";
      keys = "Settings の通知";
    }
    {
      section = "Cursor 進捗";
      label = "Agents Window";
      keys = "パレット: Open Agents Window";
    }
    {
      section = "Cursor 進捗";
      label = "ブラウザ / スマホ PWA";
      keys = "cursor.com/agents";
    }
    {
      section = "Cursor 進捗";
      label = "実行中一覧（Slack）";
      keys = "@Cursor list my agents";
    }
    # NixOS
    {
      section = "NixOS";
      label = "更新チェック（waybar upd）";
      run = "flake-update-check";
      mode = "term";
    }
    {
      section = "NixOS";
      label = "入力＋Cursor/ChatGPT 等更新";
      run = "flake-update";
      mode = "term";
    }
    {
      section = "NixOS";
      label = "適用（sudo 後・nom ETA）";
      run = "rebuild";
      mode = "term";
    }
    {
      section = "NixOS";
      label = "世代一覧";
      run = "generations";
      mode = "term";
    }
    {
      section = "NixOS";
      label = "壊れたとき → --rollback switch";
      run = "sudo nixos-rebuild --rollback switch";
      mode = "show";
    }
    {
      section = "NixOS";
      label = "時刻同期状態";
      run = "timedatectl status";
      mode = "term";
    }
    {
      section = "NixOS";
      label = "NTP 有効化（時計ずれ時）";
      run = "sudo timedatectl set-ntp true";
      mode = "show";
    }
    # 開発
    {
      section = "開発";
      label = "OpenCode";
      run = "opencode";
      mode = "term";
    }
    {
      section = "開発";
      label = "pnpm / node";
      run = "pnpm --version; node --version";
      mode = "term";
    }
    # ディスク容量
    {
      section = "ディスク容量";
      label = "df / lsblk";
      run = "df -hT /; lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS";
      mode = "term";
    }
    {
      section = "ディスク容量";
      label = "du home top";
      run = "du -xh --max-depth=1 ~ | sort -hr | head";
      mode = "term";
    }
    {
      section = "ディスク容量";
      label = "ユーザーGC（sudo不要・死んだパス）";
      run = "nix-collect-garbage";
      mode = "term";
    }
    {
      section = "ディスク容量";
      label = "旧世代削除＋GC（危険）";
      run = "sudo nix-collect-garbage -d";
      mode = "show";
    }
    {
      section = "ディスク容量";
      label = "ログ使用量（上限1G）";
      run = "journalctl --disk-usage";
      mode = "term";
    }
    {
      section = "ディスク容量";
      label = "ゴミ箱を空にする";
      run = "find ~/.local/share/Trash/files ~/.local/share/Trash/info -mindepth 1 -delete; rm -rf ~/.local/share/Trash/info && mkdir -p ~/.local/share/Trash/files ~/.local/share/Trash/info; du -sh ~/.local/share/Trash";
      mode = "term";
    }
    {
      section = "ディスク容量";
      label = "PIO download cache 削除";
      run = "rm -rf ~/.platformio/.cache && du -sh ~/.platformio";
      mode = "term";
    }
    {
      section = "ディスク容量";
      label = "npm npx キャッシュ削除";
      run = "rm -rf ~/.npm/_npx && du -sh ~/.npm";
      mode = "term";
    }
    {
      section = "ディスク容量";
      label = "PIO 版付き toolchain 重複削除";
      run = "rm -rf ~/.platformio/packages/toolchain-*@* && ls -d ~/.platformio/packages/toolchain-*";
      mode = "show";
    }
    {
      section = "ディスク容量";
      label = "Cursor agent 旧 versions 削除（最新以外）";
      run = "d=~/.config/Cursor/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions; keep=$(ls -1 \"$d\" | sort | tail -1); for x in \"$d\"/*; do [ \"$(basename \"$x\")\" = \"$keep\" ] || rm -rf \"$x\"; done; rm -rf ~/.local/share/cursor-agent/versions/*; ls \"$d\"";
      mode = "show";
    }
    {
      section = "ディスク容量";
      label = "注: ChromeOS残骸(p1/p3/p5)は root の前。拡大は LiveUSB";
    }
    # ネット・BT・WARP
    {
      section = "ネット・BT・WARP";
      label = "Wi-Fi 設定（nmtui）";
      run = nmtuiBin;
      mode = "term";
    }
    {
      section = "ネット・BT・WARP";
      label = "学校Wi-Fi: Hazamaru AP-{E,tr,U,Ryo} / eduroam（PEAP・同一PW）";
    }
    {
      section = "ネット・BT・WARP";
      label = "学校Wi-Fi 再作成（AP-EのPW流用）";
      run = "PASS=$(nmcli -s -g 802-1x.password connection show 'Hazamaru AP-E'); for n in 'Hazamaru AP-tr' 'Hazamaru AP-U' 'Hazamaru AP-Ryo'; do nmcli connection add type wifi con-name \"$n\" ifname '*' ssid \"$n\" wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 802-1x.identity s24184 802-1x.password \"$PASS\" || true; done; nmcli connection add type wifi con-name eduroam ifname '*' ssid eduroam wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 802-1x.identity s24184@tokyo-ct.ac.jp 802-1x.password \"$PASS\" || true; unset PASS";
      mode = "show";
    }
    {
      section = "ネット・BT・WARP";
      label = "全 IF の IP";
      run = "ip -br addr";
      mode = "term";
    }
    {
      section = "ネット・BT・WARP";
      label = "warp-cli connect";
      run = "warp-cli connect";
      mode = "exec";
    }
    {
      section = "ネット・BT・WARP";
      label = "warp-cli disconnect";
      run = "warp-cli disconnect";
      mode = "exec";
    }
    {
      section = "ネット・BT・WARP";
      label = "warp-cli status";
      run = "warp-cli status";
      mode = "term";
    }
    {
      section = "ネット・BT・WARP";
      label = "bluetoothctl";
      run = "bluetoothctl";
      mode = "term";
    }
    {
      section = "ネット・BT・WARP";
      label = "注: BT 音声は接続後 Pulse で出力シンクを選ぶことあり";
    }
    {
      section = "ネット・BT・WARP";
      label = "Parsec（通常）";
      run = "parsec";
      mode = "exec";
    }
    {
      section = "ネット・BT・WARP";
      label = "Parsec via Tailscale（WARP 切＋ping）";
      run = "parsec-ts";
      mode = "term";
    }
    {
      section = "ネット・BT・WARP";
      label = "ts-home-routes on（外出時だけ）";
      run = "ts-home-routes on";
      mode = "term";
    }
    {
      section = "ネット・BT・WARP";
      label = "ts-home-routes off（帰宅後）";
      run = "ts-home-routes off";
      mode = "term";
    }
    {
      section = "ネット・BT・WARP";
      label = "注: Parsec -6023 → ホスト config に app_custom_address=100.102.102.53。自宅では accept-routes 禁止";
    }
    # Windows 連携
    {
      section = "Windows 連携";
      label = "lan-mouse GUI（先に stop daemon）";
      run = "lan-mouse";
      mode = "exec";
    }
    {
      section = "Windows 連携";
      label = "stop lan-mouse";
      run = "systemctl --user stop lan-mouse";
      mode = "exec";
    }
    {
      section = "Windows 連携";
      label = "start lan-mouse";
      run = "systemctl --user start lan-mouse";
      mode = "exec";
    }
    {
      section = "Windows 連携";
      label = "uniclipboard GUI";
      run = "uniclipboard";
      mode = "exec";
    }
    {
      section = "Windows 連携";
      label = "restart uniclipd";
      run = "systemctl --user restart uniclipd";
      mode = "exec";
    }
    {
      section = "Windows 連携";
      label = "注: uniclip は --user。再起動後は GUI も開き直す";
    }
    {
      section = "Windows 連携";
      label = "注: 起動失敗(1223)→ seahorse で鍵環解錠。版上げは flake";
    }
    # バックアップ
    {
      section = "バックアップ";
      label = "backup（使い方）";
      run = "backup";
      mode = "term";
    }
    {
      section = "バックアップ";
      label = "backup unlock-key";
      run = "backup unlock-key";
      mode = "term";
    }
    {
      section = "バックアップ";
      label = "backup run";
      run = "backup run";
      mode = "term";
    }
    {
      section = "バックアップ";
      label = "backup log";
      run = "backup log";
      mode = "term";
    }
    {
      section = "バックアップ";
      label = "backup status";
      run = "backup status";
      mode = "term";
    }
    {
      section = "バックアップ";
      label = "backup snapshots";
      run = "backup snapshots";
      mode = "term";
    }
    {
      section = "バックアップ";
      label = "backup restore … --target /tmp/restore（必須・危険）";
      run = "backup restore … --target /tmp/restore";
      mode = "show";
    }
    {
      section = "バックアップ";
      label = "backup reconnect";
      run = "backup reconnect";
      mode = "term";
    }
    {
      section = "バックアップ";
      label = "backup about";
      run = "backup about";
      mode = "term";
    }
    {
      section = "バックアップ";
      label = "注: --target なしは /home/mitac を上書き（危険）";
    }
    # 電源・Type-C
    {
      section = "電源・Type-C";
      label = "輝度 40%（消費の主因を下げる）";
      run = "${brightnessctl} set 40%";
      mode = "exec";
    }
    {
      section = "電源・Type-C";
      label = "warp disconnect";
      run = "warp-cli disconnect";
      mode = "exec";
    }
    {
      section = "電源・Type-C";
      label = "bt power off";
      run = "bluetoothctl power off";
      mode = "exec";
    }
    {
      section = "電源・Type-C";
      label = "受電優先を再適用";
      run = "sudo chromebook-typec-prefer-sink";
      mode = "show";
    }
    {
      section = "電源・Type-C";
      label = "充電不可時: 抜く→mask→FORCE_SINK→挿す";
    }
    # 周辺
    {
      section = "周辺";
      label = "QtScrcpy";
      run = "QtScrcpy";
      mode = "exec";
    }
    {
      section = "周辺";
      label = "adb devices";
      run = "adb devices";
      mode = "term";
    }
    {
      section = "周辺";
      label = "ESP32 /dev/ttyUSB0（CH340・dialout 要）";
      keys = "/dev/ttyUSB0";
    }
    {
      section = "周辺";
      label = "arduino-cli compile|upload";
      run = "arduino-cli compile -b esp32:esp32:esp32";
      mode = "show";
    }
    {
      section = "周辺";
      label = "JQuake（ログイン常駐・警報で全画面）";
      run = "JQuake";
      mode = "exec";
    }
    {
      section = "周辺";
      label = "JQuake 状態（systemd）";
      run = "systemctl --user status jquake stalonetray-jquake jquake-sway-alert";
      mode = "term";
    }
    {
      section = "周辺";
      label = "警報時は swaylock 解除→全画面（緊急）";
    }
  ];

  cheatsheetDisplay =
    e:
    let
      body = if e ? keys then "${e.keys}  →  ${e.label}" else e.label;
      suffix = if e ? run then if (e.mode or "") == "show" then "  [確認]" else "  [実行]" else "";
    in
    "${e.section} │ ${body}${suffix}";

  cheatsheetJson = pkgs.writeText "sway-cheatsheet.json" (
    builtins.toJSON (
      map (e: {
        display = cheatsheetDisplay e;
        run = e.run or null;
        mode = e.mode or null;
        keys = e.keys or null;
        label = e.label;
      }) cheatsheetEntries
    )
  );

  # ghostty -e takes a single argv; command text arrives via CHEAT_RUN.
  cheatsheetTerm = pkgs.writeShellScript "sway-cheatsheet-term" ''
    set -eu
    exec ${pkgs.bash}/bin/bash -ic \
      "$CHEAT_RUN; printf '\n[Enter で閉じる] '; read -r _"
  '';
  cheatsheetShow = pkgs.writeShellScript "sway-cheatsheet-show" ''
    set -eu
    exec ${pkgs.bash}/bin/bash -ic \
      "printf '実行しません（手で入力してください）:\n  %s\n\n' \"$CHEAT_RUN\"; read -r _"
  '';

  showCheatsheet = pkgs.writeShellScript "sway-cheatsheet" ''
    set -eu
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.jq
        pkgs.libnotify
        pkgs.rofi
        pkgs.sway
        pkgs.ghostty
        pkgs.bash
      ]
    }:$PATH"
    data="${cheatsheetJson}"
    choice=$(
      jq -r '.[].display' "$data" \
        | ${rofiBin} -dmenu -i -p '?' -no-custom
    ) || exit 0
    [ -n "$choice" ] || exit 0

    entry=$(jq -c --arg c "$choice" '.[] | select(.display == $c)' "$data")
    [ -n "$entry" ] || exit 0

    run=$(jq -r '.run // empty' <<<"$entry")
    mode=$(jq -r '.mode // empty' <<<"$entry")
    keys=$(jq -r '.keys // empty' <<<"$entry")
    label=$(jq -r '.label' <<<"$entry")

    if [ -z "$run" ]; then
      if [ -n "$keys" ]; then
        notify-send -a cheatsheet "$keys" "$label"
      else
        notify-send -a cheatsheet "チートシート" "$label"
      fi
      exit 0
    fi

    case "$mode" in
      exec)
        exec swaymsg exec -- ${pkgs.bash}/bin/bash -c "$run"
        ;;
      show)
        export CHEAT_RUN="$run"
        exec ${ghosttyBin} -e ${cheatsheetShow}
        ;;
      term|*)
        export CHEAT_RUN="$run"
        exec ${ghosttyBin} -e ${cheatsheetTerm}
        ;;
    esac
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

      # Fixed autostart apps: place by criteria (ChatGPT is native Wayland).
      assigns = {
        "1" = [
          { app_id = "cursor"; }
          { app_id = "chatgpt"; }
          # Pre-Wayland launches (ozone x11 / XWayland).
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
          # Chromebook-style: 1/2/3 finger press = L/R/M;
          # tap (lrm default) already maps 2-finger tap to right click.
          tap = "enabled";
          click_method = "clickfinger";
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
        # cliphist store: home/clipboard.nix systemd user units
        # Fixed session apps (assigns: WS1 cursor/ChatGPT, WS2 vivaldi).
        # NIXOS_OZONE_WL enables Cursor's --enable-wayland-ime (Meltype/fcitx5).
        { command = "env NIXOS_OZONE_WL=1 cursor"; }
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
      # External http(s) opens (xdg-open → existing Vivaldi) set urgent but do not
      # activate across workspaces (focus_on_window_activation is smart). Raise WS2.
      for_window [app_id="vivaldi-stable" urgent=latest] focus
      # Layout-independent cheatsheet (rofi; same as waybar ?)
      # --inhibited: work even when Cursor/Electron inhibit compositor shortcuts.
      bindsym --inhibited --to-code Mod4+slash exec ${showCheatsheet}
      bindsym --inhibited --to-code Mod4+Shift+slash exec ${showCheatsheet}

      # Entered by agent-screen HUD while ChatGPT/Cursor is driving the screen.
      mode "agent-screen" {
        bindsym Escape exec ${pkgs.chatgpt-cua-indicator}/bin/agent-screen-stop
        bindsym --inhibited Escape exec ${pkgs.chatgpt-cua-indicator}/bin/agent-screen-stop
      }
      # Always-available stop (works even if mode switch failed).
      bindsym --inhibited Mod4+Escape exec ${pkgs.chatgpt-cua-indicator}/bin/agent-screen-stop
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

  # Periodic flake / .deb update probe for the side-bar upd indicator.
  systemd.user.services.flake-update-check = {
    Unit = {
      Description = "Check MySettings flake / pinned .deb updates for waybar";
      ConditionPathExists = "${flakeRoot}/flake.nix";
    };
    Service = {
      Type = "oneshot";
      ExecStart = flakeUpdateCheck;
    };
  };
  systemd.user.timers.flake-update-check = {
    Unit = {
      Description = "Periodic flake update check for waybar";
      ConditionPathExists = "${flakeRoot}/flake.nix";
    };
    Timer = {
      OnBootSec = "3min";
      OnUnitActiveSec = "6h";
      Persistent = true;
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      mainBar = {
        name = "main";
        layer = "top";
        position = "bottom";
        height = 30;
        modules-left = [
          "custom/cheatsheet"
          "sway/workspaces"
          # Backup progress next to WS (not far-right with system modules).
          "custom/restic"
          "sway/mode"
        ];
        modules-center = [ "sway/window" ];
        modules-right = [
          "cpu"
          "memory"
          "custom/keep-screen-on"
          "battery"
          "network"
          "backlight"
          "pulseaudio"
          "clock"
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
        # Keep-screen-on: marker gates swayidle auto-lock / DPMS.
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
          on-click = openTimeIs;
        };
      };
      # Right vertical bar: updates (top), AI status (center), tray (bottom).
      sideBar = {
        name = "side";
        layer = "top";
        position = "right";
        # Icon column (Nerd Font); AI module stacks icon + usage %.
        width = 34;
        modules-left = [ "custom/updates" ];
        modules-center = [ "custom/ai" ];
        modules-right = [ "tray" ];
        "custom/updates" = {
          exec = pkgs.writeShellScript "waybar-flake-updates" ''
            f="''${XDG_RUNTIME_DIR}/flake-update-status"
            if [ -s "$f" ]; then
              cat "$f"
            else
              printf '%s\n' '{"text":"","class":"idle"}'
            fi
          '';
          return-type = "json";
          interval = 30;
          signal = 9;
          hide-empty-text = true;
          tooltip = true;
          on-click = openFlakeUpdate;
        };
        # Compact AI icons + %; hover tooltip has task / usage details.
        "custom/ai" = {
          exec = waybarAiStatus;
          return-type = "json";
          interval = 5;
          tooltip = true;
          # Keep pango <span> colors from the script.
          escape = false;
        };
        tray = {
          icon-size = 16;
          spacing = 4;
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
      window.side#waybar {
        background: #0b0f14;
        color: #9fe7e7;
      }
      /* Match bar chrome; do not inherit light GTK tooltips. */
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
      #custom-cheatsheet, #cpu, #memory, #custom-keep-screen-on, #battery, #network, #backlight, #pulseaudio, #clock {
        padding: 0 8px;
        color: #9fe7e7;
        /* Stock waybar style + light GTK use white module chrome. */
        background: transparent;
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
      /* Side bar: updates (top), AI status (center), tray (bottom). */
      window.side #custom-updates,
      window.side #custom-ai,
      window.side #tray {
        padding: 4px 0;
        color: #9fe7e7;
        background: transparent;
      }
      window.side #custom-updates {
        font-family: "JetBrainsMono Nerd Font", "Noto Sans CJK JP", sans-serif;
        font-size: 13px;
        min-width: 34px;
      }
      window.side #custom-updates.available {
        color: #9fe7e7;
        background: #15383a;
        border-top: 2px solid #33c5c5;
        padding: 8px 0;
      }
      window.side #custom-ai {
        font-family: "JetBrainsMono Nerd Font", "Noto Sans CJK JP", sans-serif;
        font-size: 13px;
        min-width: 34px;
        padding: 8px 0;
      }
      window.side #custom-ai.busy {
        background: #15383a;
        border-right: 2px solid #33c5c5;
      }
      window.side #custom-ai.warning {
        border-right: 2px solid #e5c07b;
      }
      window.side #custom-ai.critical {
        background: #3a1a1e;
        border-right: 2px solid #e06c75;
      }
      window.side #tray {
        padding-top: 8px;
      }
      /* Stock #battery is white; critical blinks to white — pin transparent. */
      #battery.charging,
      #battery.plugged,
      #battery.full,
      #battery.discharging,
      #battery.warning,
      #battery.critical {
        background: transparent;
        animation: none;
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
