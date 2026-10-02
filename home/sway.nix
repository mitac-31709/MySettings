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

  # Nvim-help style reference (monospace two-column). Opened floating via Ghostty.
  cheatsheetText = pkgs.writeText "sway-cheatsheet.txt" ''
    *sway-cheatsheet*                                          Sway チートシート

    q で閉じる / Super+Shift+/ または waybar の ? で開く

    ┌─ 起動・終了 ─────────────────────────────────────────────┐
    │ Super+Return       Ghostty を起動                        │
    │ Ctrl+Alt+T         Ghostty を起動                        │
    │ Super+D / Alt+Space rofi（アプリ起動・drun）             │
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
    │ Super+V            クリップボード履歴（cliphist+rofi）   │
    │ Print              全画面スクショ → クリップボード       │
    │ Super+Shift+s      範囲スクショ（slurp）→ クリップボード │
    │ 音量キー           上げ / 下げ / ミュート                │
    │ MicMute            マイクミュート                        │
    │ 輝度キー           画面輝度 ±5%                          │
    │ Super+Shift+/      このチートシートを開く                │
    └──────────────────────────────────────────────────────────┘

    ┌─ 入力 ───────────────────────────────────────────────────┐
    │ Super+Space        Fcitx5 / Mozc 切替（IME）             │
    │ 配列               jp（xkb_layout）                      │
    │ NumLock            起動時オン                            │
    └──────────────────────────────────────────────────────────┘

    ┌─ 便利ツール ─────────────────────────────────────────────┐
    │ showmethekey       キー押下オーバーレイ（rofi から起動） │
    │ LocalSend          LAN ファイル送受信（rofi から）       │
    │ waybar [restic]    バックアップ実行中の進捗表示          │
    │ waybar ?           このチートシート                      │
    └──────────────────────────────────────────────────────────┘

    ┌─ NixOS 適用 ─────────────────────────────────────────────┐
    │ rebuild            設定を適用（~/MySettings#mitac）      │
    │ generations        世代一覧（list-generations）          │
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
    └──────────────────────────────────────────────────────────┘
    必ず --user。daemon 再起動後は GUI も落として開き直す
    （旧ポートに張り付いて接続できなくなる）。

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

  showCheatsheet = pkgs.writeShellScript "sway-cheatsheet" ''
    exec ${ghosttyBin} --class=sway-cheatsheet -e ${nvimBin} -R \
      -c 'set laststatus=0 noruler nonumber norelativenumber noshowcmd' \
      -c 'nnoremap q :qa!<CR>' \
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
          # Super+F fullscreen, Super+R resize. Super+Space stays IME.
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
          "${mod}+Shift+slash" = "exec ${showCheatsheet}";
        };

      startup = [
        { command = polkitAgent; }
        { command = "fcitx5 -d --replace"; }
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
      # Sway cheatsheet (Ghostty + nvim -R)
      for_window [app_id="sway-cheatsheet"] floating enable, sticky enable, resize set 760 720
    '';
  };

  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "bottom";
        height = 28;
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
        font-family: "JetBrainsMono Nerd Font";
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
      #custom-restic.running {
        color: #9fe7e7;
        border-bottom: 2px solid #33c5c5;
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
