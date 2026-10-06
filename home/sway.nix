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
  nvimBin = "${pkgs.neovim}/bin/nvim";
  swaylockBin = "${pkgs.swaylock}/bin/swaylock";
  swayidleBin = "${pkgs.swayidle}/bin/swayidle";
  waybarBin = "${pkgs.waybar}/bin/waybar";
  rofiBin = "${pkgs.rofi}/bin/rofi";
  polkitAgent = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1";
  pactl = "${pkgs.pulseaudio}/bin/pactl";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  grim = "${pkgs.grim}/bin/grim";
  slurp = "${pkgs.slurp}/bin/slurp";
  wlCopy = "${pkgs.wl-clipboard}/bin/wl-copy";
  lockCmd = "${swaylockBin} -f -c 0b0f14";
  rofiLauncher = "${rofiBin} -show drun";

  # Boxed reference opened floating via Ghostty + colored nvim (-u NONE).
  cheatsheetText = pkgs.writeText "sway-cheatsheet.txt" ''
    *sway-cheatsheet*                                          Sway チートシート

    q で閉じる / Super+Shift+/ または waybar の ? でもう一度で閉じる

    ┌─ 起動・終了 ─────────────────────────────────────────────┐
    │ Super+Return       Ghostty を起動                        │
    │ Ctrl+Alt+T         Ghostty を起動                        │
    │ Super+D / Alt+Space  rofi（アプリ起動・drun）            │
    │ Super+Shift+q      フォーカス中のウィンドウを閉じる      │
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
    │ Super+s/w/e        スタック / タブ / 分割レイアウト      │
    └──────────────────────────────────────────────────────────┘
    注: Super+L はロックに割当のため、右フォーカスは Super+Right。

    ┌─ ワークスペース ─────────────────────────────────────────┐
    │ Super+1 … 9        ワークスペースへ切替                  │
    │ Super+Shift+1…9    ウィンドウを WS へ移動                │
    └──────────────────────────────────────────────────────────┘

    ┌─ 自作バインド ───────────────────────────────────────────┐
    │ Super+V            履歴選択→貼り付け（cliphist+rofi）    │
    │ Print              全画面スクショ → クリップボード       │
    │ Super+Shift+s      範囲スクショ（slurp）→ クリップボード │
    │ 音量キー           上げ / 下げ / ミュート                │
    │ MicMute            マイクミュート                        │
    │ 輝度キー           画面輝度 ±5%                          │
    │ Super+Shift+/      このチートシートを開閉               │
    └──────────────────────────────────────────────────────────┘

    ┌─ 入力 ───────────────────────────────────────────────────┐
    │ Super+Space        IBus 入力ソース切替（Meltype / Mozc） │
    │ 半角/全角          Meltype 内: 英数 ⇔ 日本語             │
    │ 配列               jp（xkb_layout）                      │
    │ NumLock            起動時オン                            │
    │ 学習データ         ~/.local/share/Meltype                │
    └──────────────────────────────────────────────────────────┘

    ┌─ 便利ツール ─────────────────────────────────────────────┐
    │ showmethekey       キー押下オーバーレイ（rofi から起動） │
    │ LocalSend          LAN ファイル送受信（rofi から）       │
    │ bcat               bat（シンタックスハイライト付き cat） │
    │ waybar [restic]    バックアップ実行中の進捗表示          │
    │ waybar ?           このチートシート（再押下で閉じる）    │
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

    ┌─ Neovim（LazyVim） ──────────────────────────────────────┐
    │ Space              リーダー（どのキーマップもここから）  │
    │ Space e            エクスプローラー                      │
    │ Space ff / Space sg  ファイル検索 / 全文検索（rg）       │
    │ Space l            Lazy プラグイン UI                    │
    │ Space cf           フォーマット                          │
    │ gd / gr / K        定義へ / 参照 / ホバー                │
    │ :Lazy sync         プラグイン更新（初回もここでインストール）│
    └──────────────────────────────────────────────────────────┘
    初回はネットワーク必須。LSP は Mason ではなく nix extraPackages。

    ┌─ NixOS 適用 ─────────────────────────────────────────────┐
    │ flake-update       入力一括＋Cursor/SendAnywhere/UniClip │
    │ nix flake update   入力のみ（UniClipboard の版は動かない）│
    │ rebuild            設定を適用（~/MySettings#mitac）      │
    │ generations        世代一覧（list-generations）          │
    │ 更新で壊れたとき   sudo nixos-rebuild --rollback switch  │
    │                    または git checkout <良いコミット> --  │
    │                    flake.lock → rebuild                  │
    └──────────────────────────────────────────────────────────┘

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
    │ 鍵環ロック時       seahorse（Default Keyring を解錠）    │
    │ ピア拒否           Devices→相手→「この端末と同期」ON    │
    │                    （tray Device Sync のチェックでも可） │
    └──────────────────────────────────────────────────────────┘
    必ず --user。daemon 再起動後は GUI も落として開き直す
    （旧ポートに張り付いて接続できなくなる）。
    起動失敗（engine 1223）は鍵環未解錠が典型。再ログインか seahorse。
    「ピア拒否」は受信オフ時の正常動作。ファイル種別も both/receive に。

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
    │ 電源 短押し        suspend                               │
    │ 電源 長押し(~2.5s) poweroff                              │
    │ 電源+Back          強制ログアウト                        │
    │ 電源+Refresh       再起動                                │
    └──────────────────────────────────────────────────────────┘

    ┌─ Network（IP 確認 / 自宅はルータ DHCP 予約） ────────────┐
    │ ip -br addr        全 IF の IP（LAN/Tailscale/WARP）     │
    │ ip route           デフォルト GW（dhcp / static）        │
    │ nmcli -f IP4 device show wlp0s20f3   Wi-Fi IP/GW/DNS   │
    │ cat /sys/class/net/wlp0s20f3/address   Wi-Fi MAC        │
    │ ※接続時 MAC は固定（cloned-mac=preserve）。予約に使う    │
    │ iperf3 -s          帯域測定サーバ（TCP/UDP 5201）        │
    │ iperf3 -c HOST     クライアント（サーバ側 IP を指定）    │
    │ iperf3 -c HOST -R  下り方向も測る（reverse）             │
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

  # Minimal nvim UI + dark/cyan syntax so keys / sections / notes stand out.
  cheatsheetVim = pkgs.writeText "sway-cheatsheet.vim" ''
    set laststatus=0 noruler nonumber norelativenumber noshowcmd nolist
    set nocursorline noshowmode
    set termguicolors
    set background=dark
    syntax enable
    highlight clear
    syntax clear

    syntax match CheatTitle /^\*.*$/
    syntax match CheatHint /^q で閉じる.*$/
    syntax match CheatNote /^注:.*$/
    syntax match CheatAside /^\(注:\|q で閉じる\)\@![^┌└│*].*$/
    syntax match CheatSection /^┌─.*┐$/
    syntax match CheatBorder /^[└│].*$/ contains=CheatKey,CheatDesc,CheatPipe
    syntax match CheatPipe /│/ contained
    syntax match CheatKey /\%(^│\)\@<= *\S.\{-}\ze \{2,}/ contained
    syntax match CheatDesc / \{2,}.\{-}\ze│$/ contained

    highlight Normal guifg=#9fe7e7 guibg=#0b0f14 ctermfg=14 ctermbg=NONE
    highlight CheatTitle guifg=#9fe7e7 guibg=#0b0f14 gui=bold ctermfg=14
    highlight CheatSection guifg=#33c5c5 guibg=#0b0f14 gui=bold ctermfg=51
    highlight CheatPipe guifg=#1f4a4c guibg=#0b0f14 ctermfg=23
    highlight CheatBorder guifg=#1f4a4c guibg=#0b0f14 ctermfg=23
    highlight CheatKey guifg=#e5c07b guibg=#0b0f14 gui=bold ctermfg=221
    highlight CheatDesc guifg=#e6edf3 guibg=#0b0f14 ctermfg=255
    highlight CheatNote guifg=#e06c75 guibg=#0b0f14 gui=bold ctermfg=203
    highlight CheatHint guifg=#6b7785 guibg=#0b0f14 ctermfg=245
    highlight CheatAside guifg=#9aa7b5 guibg=#0b0f14 ctermfg=247

    nnoremap q :qa!<CR>
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
        pkgs.neovim
      ]
    }:$PATH"
    # Toggle: second ? / Super+Shift+/ closes an existing sheet.
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
    exec ghostty --class=com.mitac.SwayCheatsheet \
      --gtk-single-instance=false \
      -e nvim -u NONE -R \
      -S ${cheatsheetVim} \
      ${cheatsheetText}
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
          # Super+D → rofi (via menu). Alt+Space also opens the launcher.
          # Super+F fullscreen, Super+R resize. Super+Space stays IBus.
          "Mod1+space" = "exec ${rofiLauncher}";
          "Ctrl+Alt+t" = "exec ${ghosttyBin}";
          "${mod}+Return" = "exec ${ghosttyBin}";
          "${mod}+l" = "exec ${lockCmd}";
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
          # Floating nvim cheatsheet (also waybar ?).
          # Physical Super+Shift+/ is bindsym --to-code in extraConfig (layout-independent).
          # JP also emits keysym "question" for Shift+/; catch that here.
          "${mod}+question" = "exec ${showCheatsheet}";
        };

      startup = [
        { command = polkitAgent; }
        { command = "ibus-daemon -drx"; }
        { command = "wl-paste --type text --watch cliphist store"; }
        { command = "wl-paste --type image --watch cliphist store"; }
        { command = waybarBin; }
        {
          command = ''
            ${swayidleBin} -w \
              timeout 600 '${lockCmd}' \
              timeout 900 'swaymsg "output * power off"' \
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
      # Sway cheatsheet (Ghostty + colored nvim -R)
      for_window [app_id="com.mitac.SwayCheatsheet"] floating enable, sticky enable, resize set 760 800
      # Layout-independent Super+Shift+/ (same toggle as waybar ?)
      bindsym --to-code Mod4+Shift+slash exec ${showCheatsheet}
    '';
  };

  programs.waybar = {
    enable = true;
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
          "battery"
          "network"
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
        cpu = {
          format = "cpu {usage}%";
          interval = 5;
        };
        memory = {
          format = "mem {percentage}%";
          interval = 5;
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
          format-wifi = "{essid}";
          format-ethernet = "eth";
          format-disconnected = "offline";
          tooltip-format = "{ifname}: {ipaddr}";
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
      #custom-cheatsheet, #cpu, #memory, #battery, #network, #pulseaudio, #clock, #tray {
        padding: 0 8px;
        color: #9fe7e7;
      }
      #custom-cheatsheet {
        color: #33c5c5;
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
