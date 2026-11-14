{
  config,
  pkgs,
  lib,
  flakeTarget ? "chromebook",
  ...
}:
let
  machine = import ../../lib/machine.nix;
  hiraginoDir = machine.hiraginoDir;
  # Pure eval cannot read an absolute path outside the flake: pathExists is
  # false, so `nix flake check` and machines without the fonts still evaluate.
  # rebuild adds --impure when the directory exists. pathExists is then real,
  # and builtins.path copies the OTFs into the store.
  hiraginoEnabled = builtins.pathExists hiraginoDir;
  hasBtrfs = lib.any (fs: (fs.fsType or null) == "btrfs") (lib.attrValues config.fileSystems);
in
{
  imports = [
    ./secrets.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable monthly scrub automatically once a host's hardware-configuration uses btrfs.
  services.btrfs.autoScrub = lib.mkIf hasBtrfs {
    enable = true;
    interval = "monthly";
  };

  # Live systemd job tree on the boot console (flake input `bootvine`).
  # This nixpkgs pin is NixOS 26.11, where the initrd is systemd-only, so the
  # module covers the initrd without boot.initrd.systemd.enable (removed).
  services.bootvine.enable = true;

  # Distinct per-host hostname (chromebook / vaio) avoids Avahi/mDNS, Tailscale,
  # RQuickShare, and Chromium SingletonLock collisions across machines.
  networking.hostName = lib.mkDefault flakeTarget;
  networking.networkmanager.enable = true;

  # Avoid leaving networking down if activation stops NM then fails mid-switch
  # (seen with switch-to-configuration exit 101).
  systemd.services.NetworkManager = {
    wantedBy = [ "multi-user.target" ];
    stopIfChanged = false;
  };

  # Prefer reclaiming user/session memory under pressure before the whole machine
  # thrashing (8 GiB Chromebook + browsers).
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableSystemSlice = true;
    enableUserSlices = true;
  };

  # Cap journald disk use so logs cannot grow without bound.
  services.journald.settings.Journal = {
    SystemMaxUse = "1G";
    RuntimeMaxUse = "100M";
  };

  time.timeZone = "Asia/Tokyo";
  # Chromebook RTC can wake in the past (seen as 2024-01-24) until NTP lands;
  # TLS then fails with "certificate is not yet valid". Keep timesyncd on.
  services.timesyncd.enable = true;

  i18n.defaultLocale = "ja_JP.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ja_JP.UTF-8";
    LC_IDENTIFICATION = "ja_JP.UTF-8";
    LC_MEASUREMENT = "ja_JP.UTF-8";
    LC_MONETARY = "ja_JP.UTF-8";
    LC_NAME = "ja_JP.UTF-8";
    LC_NUMERIC = "ja_JP.UTF-8";
    LC_PAPER = "ja_JP.UTF-8";
    LC_TELEPHONE = "ja_JP.UTF-8";
    LC_TIME = "ja_JP.UTF-8";
  };

  # Fcitx5 + Meltype only — Sway Wayland
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      meltype
      fcitx5-gtk
      kdePackages.fcitx5-qt
      kdePackages.fcitx5-configtool
    ];
    fcitx5.settings.inputMethod = {
      GroupOrder."0" = "Default";
      "Groups/0" = {
        Name = "Default";
        "Default Layout" = "jp";
        DefaultIM = "meltype";
      };
      # Meltype only (no mozc / keyboard-jp). Electron (ChatGPT) often cannot
      # reactivate IME after switching to keyboard-only, so keep keyboard out.
      "Groups/0/Items/0".Name = "meltype";
    };
    # Avoid Super+Shift / lone-Shift hotkeys that steal compositor chords
    # (Win+Shift+q, etc.) on the same seat as Sway.
    fcitx5.settings.globalOptions = {
      # Electron + text-input-v3: per-IC active/inactive desyncs; share globally
      # so ChatGPT can leave "English" and return to Meltype.
      Behavior.ShareInputState = "All";
      Behavior.ActiveByDefault = true;
      # Super+Space = Fcitx Trigger (active ⇔ inactive). With only Meltype in
      # the group, both sides stay Meltype. Do NOT bind Zenkaku_Hankaku here —
      # that key belongs to Meltype's internal 英数⇔日本語 toggle.
      "Hotkey/TriggerKeys"."0" = "Super+space";
      "Hotkey/AltTriggerKeys" = { };
      "Hotkey/EnumerateForwardKeys" = { };
      "Hotkey/EnumerateBackwardKeys" = { };
      "Hotkey/EnumerateGroupForwardKeys"."0" = "Control+Shift+space";
      "Hotkey/EnumerateGroupBackwardKeys" = { };
    };
  };

  # Electron (Cursor, etc.): nixpkgs wrappers only pass --enable-wayland-ime
  # when this is set. Without it Cursor still picks Wayland but does not wire
  # text-input to fcitx5, so Meltype cannot compose. Restart Cursor fully
  # after changing this (single-instance ignores flags on --new-window).
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  fonts.packages =
    with pkgs;
    [
      nerd-fonts.jetbrains-mono
      noto-fonts-color-emoji
      # Typst / docs often request "Noto Sans CJK JP" by name.
      # Also the sans / mono fallback when Hiragino is not installed.
      noto-fonts-cjk-sans
      # Serif fallback (Hiragino Mincho ProN) when the local OTFs are absent.
      noto-fonts-cjk-serif
    ]
    ++ lib.optionals hiraginoEnabled [
      (pkgs.callPackage ../../pkgs/hiragino {
        src = builtins.path {
          path = hiraginoDir;
          name = "hiragino-otf";
          filter = path: type: type == "directory" || lib.hasSuffix ".otf" (lib.toLower path);
        };
      })
    ];
  # First family wins when it is installed. Missing families are skipped,
  # so Noto CJK is the default whenever Hiragino is not in fonts.packages.
  fonts.fontconfig.defaultFonts = {
    sansSerif = [
      "Hiragino Kaku Gothic ProN"
      "Noto Sans CJK JP"
    ];
    serif = [
      "Hiragino Mincho ProN"
      "Noto Serif CJK JP"
    ];
    monospace = [
      "JetBrainsMono Nerd Font"
      "Hiragino Kaku Gothic ProN"
      "Noto Sans CJK JP"
    ];
    emoji = [ "Noto Color Emoji" ];
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # Affinity is not installed (input and overlay removed; see README).
    # Do not hard-depend on cache.forall.systems — a wrong RTC before NTP
    # makes every fetch fail with SSL "certificate is not yet valid", and
    # misses also stall rebuild. When re-enabling affinity-v3, restore:
    #   extra-substituters = [ "https://cache.forall.systems" ];
    #   extra-trusted-public-keys = [
    #     "cache.forall.systems:5PmD7QO4MSF8YgyRZtkSGXRDo96H3bybIf2SsQh8ScI="
    #   ];
  };

  users.users.mitac = {
    isNormalUser = true;
    description = "mitac";
    extraGroups = [
      "networkmanager"
      "render"
      "video"
      "wheel"
      "systemd-journal" # restic backup notify reads unit logs for progress/summary
      "dialout" # /dev/ttyUSB* / ttyACM* (ESP32, Arduino, …)
    ];
    # Set a password after first boot: passwd mitac
  };

  environment.systemPackages =
    with pkgs;
    [
      # git and vim stay on the system profile for root and recovery shells.
      # sudo's secure_path is /run/current-system/sw/bin and does not include
      # the user Home Manager profile. programs.git (home/programs.nix) is the
      # user's git, with name and email; this package is the unconfigured one.
      vim
      git
      wget
      curl
      alsa-utils # amixer/alsactl — mute SOF amps if audio wedges
      libva-utils # vainfo — verify VA-API / Parsec hw encode
      iperf3 # LAN / WAN bandwidth test (server: -s, client: -c HOST)
    ]
    ++ lib.optionals hasBtrfs [ compsize ];

  # Cloudflare WARP (1.1.1.1): daemon + CLI, plus official GUI (warp-taskbar tray).
  services.cloudflare-warp.enable = true;
  # Upstream unit provides BindReadOnlyPaths=…:/usr: so warp-taskbar finds
  # /usr/share/warp/images. It also ships warp-svc — disable that duplicate;
  # NixOS owns cloudflare-warp.service.
  systemd.packages = [ pkgs.cloudflare-warp ];
  systemd.services.warp-svc.enable = false;
  # Tray needs a StatusNotifier host (waybar). Start in every graphical
  # session (manual launch without /usr bind dies).
  systemd.user.services.warp-taskbar = {
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session-pre.target" ];
    # Logout: tray dies then Restart (upstream unit) storms without a limit.
    unitConfig = {
      PartOf = [ "graphical-session.target" ];
      BindsTo = [ "graphical-session.target" ];
      StartLimitIntervalSec = "30";
      StartLimitBurst = "3";
    };
  };

  # Tailscale daemon; Trayscale (GUI) is in home.packages.
  # --operator lets the login user run `tailscale file get` (Taildrop) without sudo.
  services.tailscale = {
    enable = true;
    extraSetFlags = [ "--operator=mitac" ];
  };

  # Steam needs the NixOS module (32-bit libs, FHS, steam-hardware).
  # Also pulls in hardware.graphics.enable32Bit, which Bottles/Wine need.
  programs.steam.enable = true;

  # LocalSend (LAN file transfer); opens TCP/UDP 53317 by default.
  programs.localsend.enable = true;

  # Lan Mouse (software KVM from Windows); default UDP 4242.
  # iperf3 server defaults to TCP/UDP 5201.
  networking.firewall.allowedTCPPorts = [ 5201 ];
  networking.firewall.allowedUDPPorts = [
    4242
    5201
  ];

  hardware.enableRedistributableFirmware = true;

  # Pre-populate verified SSH host public keys in /etc/ssh/ssh_known_hosts
  # so clients don't rely solely on mutable ~/.ssh/known_hosts.
  programs.ssh.knownHosts =
    let
      knownHostSpecs = {
        galleria-mitac-wsl = {
          hostNames = [
            "[galleria-mitac]:2222"
            "[100.102.102.53]:2222"
          ];
          keys = {
            ed25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID+Dgx7oDIHOa5CPTkDbeGqIjGsCf2evYSI/pRIjz7H0";
            ecdsa = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFLPfYzIfOIyrYtT8tObRvQO1vb/XMCTkcNUs4PnviQ4iVJ6BRxLScfMAYikqlyeVTcCzNEy+FQ3/kFTBd92LSY=";
            rsa = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDfpApYB38avxk4++jCX2neAP6Yv4/oKafbO2ROlTVilSXGookWRRv5TM7W2bq0TstgKd0P7Jvg/Q1U9WzssAGNzdgWsCAYKeMItcxsx2V6WRTs/GFaduPCnPSlqovFjLG6gHzXUXAnaWc2eT78tPfFsLPCVscv1s3jrakHcUMOJDcX1IaThlrPsSNVRJ/IZC4SUi2M3JWWNi16y/LX5WHLV9YTFBy9D6pJnf8+/llDK3Q0J/5daOHscTTrVuP/6i1eAK9dlcUJqcGyW0qcnPCH5RfPaY5ezBYjhjHefgjOS8P9nK3lqD0r4dEKX2wupZ2GFF8TDAYAqncAozjx+9LJCo5VMTbcqkSqUFFfIOqybg3wCv8UvIdVjlKQf98v4POPWhPuyijgsHCO0+ICuiLoHs/7P8/yKs3GpEC/W/7jZqbYao0X2jRxmSUjER1YolYiUegR6a/Tye4QwUjSDWxK2DmTSonF1rfyAugY7MyJE+h2Zte49Jb1JYxmdPLJ07k=";
          };
        };
        ubuntu = {
          hostNames = [
            "100.124.196.22"
            "ubuntu"
          ];
          keys = {
            ed25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHSTbPRFFlZw/Lc0o4CPsaSZpFNnP2/+B67QuwcWkSEH";
            ecdsa = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOy8Dq6p16YoLs701NKMCp3p9vWeWyn+t97uJMTOdcH+K/qIRPxlY5mjCgDJK4Vxt3Fgap6tZZldbRCGECDGfTA=";
            rsa = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCy0KxAon1lH6rjQKYFzPM9eOQ+y9Rd+aNlSiq7JhwrUd9qhxRpl0yRJA1DfC/Vbt9EgpWFAgSlh+NW9hdzYfr80jS8h/xrUUsMwoP4Sxb1FLtdqW3DTt3c/uuMdkNjpG0PDNdomHyfxU5HZUBwRmWU7Kyfx1whYQEF+RPJxI/BiXxmyfbQ97HlOG+oggaufH7Amoeqv3UXgfggA9xLONjmyeo7/TXYZKzvjyEN6yElgjI0zAzigz79OzQsqLHYllMTYsoTlY9v1oDjU8yGACDbUsYOqN08g0tTsPIDRDb4e81HdQJ3T/tNw2JvwcjR+wZJLjK1D9HbzpIIEiIqnDIg2PTuFAQBu9Prlm63QnLFytSbEGBhUWqkFYZv+3HjSuwSJxGVZozaTMG4LpyFGql+Iv2ZJASqMBgMd/U56JXc+yAPdx0pg65coHRYcqfjH9+3RlHYW62V1x/ShLuMTyKx4/BE8Uy9B2+jcqGBfbuYLR+Mk1RBiI4A59JdYvl8tAc=";
          };
        };
        raspberrypi = {
          hostNames = [
            "100.71.240.112"
            "raspberrypi"
            "172.18.46.146"
          ];
          keys = {
            ed25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJvCFYDYl5bZWqCpJzrjKzrnJSk2mjGQJ/1xHad1PvsN";
            ecdsa = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBeL6WwcmX4K/r5aY6Lhh2kyj3ri82rqjlWvYEmNTIQq/JZIjE8ra2+0gm38cG99LwdVDAXtBV6tsJb8vhCKJLw=";
            rsa = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCcPNwgD4BRwMxXcBEWxyXMvMH18IQPXhQ1x4xt0mruJYfH7i0ZB0bwWeKXpLL0tvCcfRFtMRV+JJa2ilyLE8W3SVu1WXhpQab1F/uFqa+Ck6pY3XWj+kb42nkpRxXNVmmv3RFYLPQTaWeuq71lD5WXa4RsIvHsM4RxvlxdojNxYz8dxc3HM58onAZLHYZ6JfZxDwAuXV6zM5+m6L+jbZi1jipsLOSa/pDm1/JlZYNwsLlbCavp50r+fGZjSGCexXgfHiR0D5GuLYV7jw+VIewuWzEHff7SwUyyojrUSdThbWpQs1QLMxe9ecUxzBQfTavEHecL19DnpzMRSc21SUUGdfOI56I8rhcIZGmtx14d+th3cesxp6ToM4Ehn8+cAvP21JRlxbkKKI5lOKcwSwsWtYa6XnPf2n9NfMPO/NUknu/12K7eZhrIskTv44YuYhcUCeNE/HQNgQ7r1cgG+thmLxU6s8Jnfs72jIBc7MEPgHnrdWgC7KgjCOwCioeOBG0=";
          };
        };
        lan-172-18-43-172 = {
          hostNames = [ "172.18.43.172" ];
          keys = {
            ed25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIQYPYm11vnHbWzIx+nVFmOBIgGtuNLdb83dSK7H3j3a";
            ecdsa = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBB0gRCxomoetliuRS12CIoNQE40RdsXKa47Emn4/GCHKRXtdJhmfMbuEGENmbQ9CVIJcDjp+iw8QfUfCwa7adY8=";
            rsa = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC9cmaJZK/Lj3LhXjX4G5CS4zf7j+fzr4OXrmsCz1ZSmRWPt4TP+aeFC8MWloW0sbj/f4DlkvpDB9prvflsAUkPKVaRowq30HvonTofr+u49RrSwNl5lUp8VXztjwIdWmFCQSPry8rgHtbsooNfM/ebWrggnnr7Wbd791Thn2F8NqtU9v4MkP6XsOIgZBr2tB5muWzJXLUYjzhKJ7htGSNpQOvi3v6+IIV9f7+t+CEg5B+M8yKOM4sTFkLpj0HYmXTwF1r+/ENzalYKAgzYRRSNEOD6kDIad5NIkGz/MQV/84ozFYI5PiKFRRsCFlqUjkaN/zBTQ/1X8+PHAXPR66oWyCZJ5QiRy5M7HwZlOIeZE6bz9zA3wkO56VEbmupIWzhy7LsB9fKhK9W6K4D3RIVHNM72eT2Xzs21tLxuXOK0z+8RGqFl4TjlZf/uwn8Kfs2Wo1Fz/HWgFLfEMWIi2WFU67W0lpCutO5hNgugULaKdYUkX7gM7EkjYeaOlToxQi0=";
          };
        };
      };
    in
    pkgs.lib.concatMapAttrs (
      host: spec:
      pkgs.lib.mapAttrs' (algo: key: {
        name = "${host}-${algo}";
        value = {
          inherit (spec) hostNames;
          publicKey = key;
        };
      }) spec.keys
    ) knownHostSpecs;

  services.openssh.enable = false;
}
