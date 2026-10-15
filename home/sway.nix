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
    │ Super+Return / Ctrl+Alt+T   Ghostty                      │
    │ Super+D / Alt+Space         rofi（選択中 WS に起動）     │
    │ Super+q                     ウィンドウを閉じる           │
    │ Super+L                     画面ロック                   │
    │ Super+Shift+c / e           設定再読込 / Sway 終了       │
    │ Super+/                     このシート開閉（waybar ?）   │
    └──────────────────────────────────────────────────────────┘
    注: ELECOM は Win+Shift 同時押しが欠けること有 → Super+q 等。

    ┌─ ウィンドウ・WS ─────────────────────────────────────────┐
    │ Super+hjkl / 矢印           フォーカス（右は Right）     │
    │ Super+Shift+hjkl            ウィンドウ移動               │
    │ Super+f / r                 フルスクリーン / リサイズ    │
    │ Super+Shift+Space           フローティング切替           │
    │ Super+b / v                 水平 / 垂直分割              │
    │ Super+s / w                 スタック / タブ              │
    │ Super+1…9 / Shift+1…9       WS 切替 / ウィンドウを移動   │
    │ 起動時                      WS1 Cursor+GPT / WS2 Vivaldi │
    └──────────────────────────────────────────────────────────┘
    注: Super+e は既定の分割ではなく Yazi。

    ┌─ スクショ・音量・輝度・履歴 ─────────────────────────────┐
    │ Print                       全画面 → クリップボード      │
    │ Super+Shift+s               範囲選択 → クリップボード    │
    │ Super+V                     クリップボード履歴（rofi）   │
    │ 音量 / MicMute / 輝度キー   ± / ミュート / 輝度 ±5%      │
    └──────────────────────────────────────────────────────────┘

    ┌─ 入力・Chromebook キー ──────────────────────────────────┐
    │ Super+Space                 IME 切替（Meltype / Mozc）   │
    │ 半角/全角                   Meltype 内: 英数 ⇔ 日本語    │
    │ 学習データ                  ~/.local/share/Meltype       │
    │ 2本指タップ・押下           右クリック（Chromebook）     │
    │ Search+最上段               F1–F10（3つ目=セッション）   │
    │ Ctrl+Alt+Del                手動 OOM（内蔵=C-A-Bksp）    │
    │ 電源 短/長押し              suspend / poweroff           │
    │ 電源+Back / +Refresh        強制ログアウト / 再起動      │
    │ ELECOM Fn+Q / Fn+W          Windows / Mac モード         │
    │ 外付け KB 接続時            内蔵 KB は自動無効           │
    └──────────────────────────────────────────────────────────┘
    注: ELECOM を Mac のままにすると Ctrl↔Win が入れ替わる。

    ┌─ Yazi / Neovim ──────────────────────────────────────────┐
    │ Super+e                     Yazi（Ghostty 内）           │
    │ . / Tab / Enter             隠し表示 / spot / 開く       │
    │ ; / : / f / z               シェル / フィルタ / zoxide   │
    │ y（bash）                   終了後その dir へ cd         │
    │ Space                       nvim リーダー                │
    │ Space e / ff / sg           ツリー / ファイル / 全文検索 │
    │ gd / gr / K                 定義 / 参照 / ホバー         │
    └──────────────────────────────────────────────────────────┘

    ┌─ Waybar・日常 ───────────────────────────────────────────┐
    │ ? / scr                     チートシート / 常時オン切替  │
    │ cpu·mem / net / bri         クリック→btop / nmtui / 輝度 │
    │ [restic]（WS の右）         バックアップ進捗             │
    │ 無操作                      10分ロック / 15分画面オフ    │
    │ LocalSend / showmethekey    LAN 送受信 / キー表示（rofi）│
    │ ChatGPT / Grok / DeepSeek   AI（rofi から）              │
    └──────────────────────────────────────────────────────────┘

    ┌─ NixOS ──────────────────────────────────────────────────┐
    │ flake-update                入力＋Cursor/ChatGPT 等更新  │
    │ rebuild                     適用（sudo 後・nom ETA）     │
    │ generations                 世代一覧                     │
    │ 壊れたとき                  --rollback switch            │
    └──────────────────────────────────────────────────────────┘

    ┌─ ディスク容量 ───────────────────────────────────────────┐
    │ df -hT / ; lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS         │
    │ du -xh --max-depth=1 ~ | sort -hr | head                 │
    │ sudo nix-collect-garbage -d   旧世代削除＋GC             │
    │ journalctl --disk-usage       ログ使用量（上限1G）       │
    │ 注: ChromeOS残骸(p1/p3/p5)は root の前。拡大は LiveUSB  │
    └──────────────────────────────────────────────────────────┘

    ┌─ ネット・BT・WARP ───────────────────────────────────────┐
    │ nmtui / ip -br addr         Wi-Fi 設定 / 全 IF の IP     │
    │ warp-cli connect|disconnect|status                       │
    │ bluetoothctl                power/scan/pair/connect      │
    └──────────────────────────────────────────────────────────┘
    注: BT 音声は接続後 Pulse で出力シンクを選ぶことあり。

    ┌─ Windows 連携 ───────────────────────────────────────────┐
    │ lan-mouse                   GUI（先に stop daemon）      │
    │ systemctl --user stop|start lan-mouse                    │
    │ uniclipboard / restart uniclipd   GUI / daemon 再起動    │
    └──────────────────────────────────────────────────────────┘
    注: uniclip は --user。再起動後は GUI も開き直す。
    注: 起動失敗(1223)→ seahorse で鍵環解錠。版上げは flake。

    ┌─ バックアップ（restic → Drive） ─────────────────────────┐
    │ backup / unlock-key / run   使い方 / 鍵 / 実行           │
    │ backup log / status / snapshots                          │
    │ backup restore … --target /tmp/restore   ※必須           │
    │ backup reconnect / about    OAuth 再接続 / 疎通          │
    └──────────────────────────────────────────────────────────┘
    注: --target なしは /home/mitac を上書き（危険）。

    ┌─ 電源・Type-C ───────────────────────────────────────────┐
    │ brightnessctl set 40%       輝度下げ（消費の主因）       │
    │ warp disconnect / bt power off   不要なら切る            │
    │ sudo chromebook-typec-prefer-sink   受電優先を再適用     │
    │ 充電不可時                  抜く→mask→FORCE_SINK→挿す    │
    └──────────────────────────────────────────────────────────┘

    ┌─ 周辺（VM / Android / ESP32） ───────────────────────────┐
    │ virt-manager / virsh list --all                          │
    │ QtScrcpy / adb devices      ミラー（USB デバッグ ON）    │
    │ /dev/ttyUSB0                ESP32（CH340・dialout 要）   │
    │ arduino-cli compile|upload -b esp32:esp32:esp32          │
    └──────────────────────────────────────────────────────────┘
  '';

  # q/Q quit only. Do NOT bind bare Esc here: with --mouse, click CSI sequences
  # start with ESC and race the lone-\e binding, so the sheet vanishes on click.
  # Esc→close is done via Ghostty --keybind=escape=text:q instead.
  cheatsheetLesskey = pkgs.writeText "sway-cheatsheet.lesskey" ''
    #command
    q quit
    Q quit
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
        - match: '^(※|注:).*$'
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
  cheatsheetBatHome =
    pkgs.runCommand "sway-cheatsheet-bat-home" { nativeBuildInputs = [ pkgs.bat ]; }
      ''
        mkdir -p $out/config/syntaxes $out/cache
        cp ${cheatsheetSyntax} $out/config/syntaxes/SwayCheatsheet.sublime-syntax
        export BAT_CONFIG_DIR=$out/config
        export XDG_CACHE_HOME=$out/cache
        bat cache --build
      '';

  # Single argv for ghostty -e (multi-arg -e is easy to break; breaks keys/pager).
  cheatsheetViewer = pkgs.writeShellScript "sway-cheatsheet-view" ''
    set -eu
    export PATH="${
      lib.makeBinPath [
        pkgs.bat
        pkgs.less
        pkgs.coreutils
      ]
    }:$PATH"
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
    # escape=text:q: Esc closes without lesskey \e (which breaks --mouse clicks).
    exec ghostty --class=com.mitac.SwayCheatsheet \
      --gtk-single-instance=false \
      --font-family="JetBrainsMono Nerd Font" \
      --font-family="Noto Sans Mono CJK JP" \
      --window-padding-x=8 \
      --window-padding-y=8 \
      --keybind=escape=text:q \
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
          # Chromebook / Plasma parity: 1/2/3 finger press = L/R/M;
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
      for_window [app_id="com.mitac.SwayCheatsheet"] floating enable, sticky enable, resize set 720 780, move position center
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
        /* Stock waybar style + Plasma light GTK use white module chrome. */
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
