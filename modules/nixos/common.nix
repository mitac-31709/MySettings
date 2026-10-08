{
  config,
  pkgs,
  ...
}:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "NixOS";
  networking.networkmanager.enable = true;

  # Avoid leaving networking down if activation stops NM then fails mid-switch
  # (seen with switch-to-configuration exit 101).
  systemd.services.NetworkManager = {
    wantedBy = [ "multi-user.target" ];
    stopIfChanged = false;
  };

  # Prefer reclaiming user/session memory under pressure before the whole machine
  # thrashing (8 GiB Chromebook + Plasma + browsers).
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

  # Fcitx5 + Mozc (works well with Plasma Wayland)
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      fcitx5-mozc
      fcitx5-gtk
      kdePackages.fcitx5-qt
      kdePackages.fcitx5-configtool
    ];
    fcitx5.settings.inputMethod = {
      GroupOrder."0" = "Default";
      "Groups/0" = {
        Name = "Default";
        "Default Layout" = "jp";
        DefaultIM = "mozc";
      };
      "Groups/0/Items/0".Name = "keyboard-jp";
      "Groups/0/Items/1".Name = "mozc";
    };
    # Avoid Super+Shift / lone-Shift hotkeys that steal compositor chords
    # (Win+Shift+q, etc.) on the same seat as Sway.
    fcitx5.settings.globalOptions = {
      "Hotkey/AltTriggerKeys" = { };
      "Hotkey/EnumerateForwardKeys" = { };
      "Hotkey/EnumerateBackwardKeys" = { };
      "Hotkey/EnumerateGroupForwardKeys"."0" = "Control+Shift+space";
      "Hotkey/EnumerateGroupBackwardKeys" = { };
    };
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts-color-emoji
    hiragino-fonts
  ];
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Hiragino Kaku Gothic ProN" ];
    serif = [ "Hiragino Mincho ProN" ];
    monospace = [
      "JetBrainsMono Nerd Font"
      "Hiragino Kaku Gothic ProN"
    ];
    emoji = [ "Noto Color Emoji" ];
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # Binary cache for affinity-nix (Wine Affinity builds).
    extra-substituters = [ "https://cache.forall.systems" ];
    extra-trusted-public-keys = [
      "cache.forall.systems:5PmD7QO4MSF8YgyRZtkSGXRDo96H3bybIf2SsQh8ScI="
    ];
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

  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
    alsa-utils # amixer/alsactl — mute SOF amps if audio wedges
    libva-utils # vainfo — verify VA-API / Parsec hw encode
    iperf3 # LAN / WAN bandwidth test (server: -s, client: -c HOST)
  ];

  # Cloudflare WARP (1.1.1.1): daemon + CLI, plus official GUI (warp-taskbar tray).
  services.cloudflare-warp.enable = true;
  # Upstream unit provides BindReadOnlyPaths=…:/usr: so warp-taskbar finds
  # /usr/share/warp/images. It also ships warp-svc — disable that duplicate;
  # NixOS owns cloudflare-warp.service.
  systemd.packages = [ pkgs.cloudflare-warp ];
  systemd.services.warp-svc.enable = false;
  # Tray needs a StatusNotifier host (waybar / Plasma). Start in every
  # graphical session — not KDE-only (manual launch without /usr bind dies).
  systemd.user.services.warp-taskbar = {
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session-pre.target" ];
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

  services.openssh.enable = false;
}
