{
  config,
  pkgs,
  ...
}:

{
  networking.hostName = "mitac";
  networking.networkmanager.enable = true;

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

  # IBus + Mozc (add Japanese (Mozc) in GNOME Settings → Keyboard → Input Sources)
  i18n.inputMethod = {
    enable = true;
    type = "ibus";
    ibus.engines = with pkgs.ibus-engines; [ mozc ];
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

  hardware.enableRedistributableFirmware = true;

  services.openssh.enable = false;
}
