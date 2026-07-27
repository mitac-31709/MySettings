{
  config,
  pkgs,
  ...
}:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "mitac";
  networking.networkmanager.enable = true;

  # Avoid leaving networking down if activation stops NM then fails mid-switch
  # (seen with switch-to-configuration exit 101).
  systemd.services.NetworkManager = {
    wantedBy = [ "multi-user.target" ];
    stopIfChanged = false;
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
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts-color-emoji
  ];
  fonts.fontconfig.defaultFonts = {
    monospace = [ "JetBrainsMono Nerd Font" ];
    emoji = [ "Noto Color Emoji" ];
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  users.users.mitac = {
    isNormalUser = true;
    description = "mitac";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    # Set a password after first boot: passwd mitac
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
  ];

  # Steam needs the NixOS module (32-bit libs, FHS, steam-hardware).
  programs.steam.enable = true;

  hardware.enableRedistributableFirmware = true;

  services.openssh.enable = false;
}
