{
  description = "NixOS configuration for mitac (multi-session: Sway/Plasma, Chromebook delbin)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # ChromeOS ALSA UCM overlays (sof-rt5682 etc. for volteer/delbin)
    alsa-ucm-conf-cros = {
      url = "github:WeirdTreeThing/alsa-ucm-conf-cros/standalone";
      flake = false;
    };
    # Affinity Photo/Designer/Publisher (Wine; Canva Affinity v3)
    affinity-nix.url = "github:mrshmllow/affinity-nix"; # Fresher nixpkgs solely for Cursor packages (avoid bumping the whole system).
    nixpkgs-cursor.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Vendor .debs (flake update re-fetches; see scripts/flake-update.sh).
    # Keep URL version in sync with uniclipboardVersion below (flake-update.sh).
    uniclipboard-deb = {
      url = "https://github.com/UniClipboard/UniClipboard/releases/download/v1.1.2/UniClipboard_1.1.2_amd64.deb";
      flake = false;
    };
    # Keep URL version in sync with chatgptVersion below (flake-update.sh).
    chatgpt-deb = {
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1013.40934_amd64.deb";
      flake = false;
    };
    # Keep URL version in sync with grokBotVersion below (flake-update.sh).
    grok-bot-deb = {
      url = "https://downloads.cursor.com/grokbot/stable/6a17bb448f856a2390dd63ba42bf6e80e63b08fd/linux/x64/grok-bot_0.72.0_amd64.deb";
      flake = false;
    };
    # Proprietary Hiragino OTFs (local; not committed). Prepare with:
    #   extract ~/Documents/ヒラギノ.zip → ~/Documents/hiragino-otf/*.otf (ASCII names)
    hiragino-fonts-src = {
      url = "path:/home/mitac/Documents/hiragino-otf";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      alsa-ucm-conf-cros,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      # Must match inputs.uniclipboard-deb URL (updated by scripts/flake-update.sh).
      uniclipboardVersion = "1.1.2";
      # Must match inputs.chatgpt-deb URL (updated by scripts/flake-update.sh).
      chatgptVersion = "26.1013.40934";
      # Must match inputs.grok-bot-deb URL (updated by scripts/flake-update.sh).
      grokBotVersion = "0.72.0";
    in
    {
      nixosConfigurations.mitac = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/mitac
          home-manager.nixosModules.home-manager
          {
            # Links this generation to a git commit (shows in
            # `nixos-rebuild list-generations` / `nixos-version --json`).
            # Uncommitted trees get dirtyRev / dirtyShortRev; clean trees get rev.
            system.configurationRevision = self.rev or self.dirtyRev or "dirty";

            nixpkgs.config.allowUnfree = true;
            nixpkgs.overlays = [
              inputs.affinity-nix.overlays.default
              (
                final: prev:
                let
                  # Electron app + Agent CLI; pull latest Cursor without a full nixpkgs bump.
                  cursorPkgs = import inputs.nixpkgs-cursor {
                    system = prev.stdenv.hostPlatform.system;
                    config.allowUnfree = true;
                  };
                in
                {
                  inherit (cursorPkgs) code-cursor cursor-cli;
                  uniclipboard = final.callPackage ./pkgs/uniclipboard {
                    src = inputs.uniclipboard-deb;
                    version = uniclipboardVersion;
                  };
                  hiragino-fonts = final.callPackage ./pkgs/hiragino {
                    src = inputs.hiragino-fonts-src;
                  };
                  # Meltype Linux preview as Fcitx5 addon (not in nixpkgs).
                  meltype = final.callPackage ./pkgs/meltype { };
                  # Official ChatGPT Linux desktop (Codex included); overrides darwin-only nixpkgs attr.
                  chatgpt = final.callPackage ./pkgs/chatgpt {
                    src = inputs.chatgpt-deb;
                    version = chatgptVersion;
                  };
                  # Sway HUD while ChatGPT / Cursor screen agents drive the desktop.
                  chatgpt-cua-indicator = final.callPackage ./pkgs/chatgpt-cua-indicator { };
                  # Official Grok Bot Linux desktop (Cursor / x.ai).
                  grok-bot = final.callPackage ./pkgs/grok-bot {
                    src = inputs.grok-bot-deb;
                    version = grokBotVersion;
                  };
                  # 1.8.4 + Sway AWT / sounds / no-update-prompt wrapper.
                  jquake = final.callPackage ./pkgs/jquake { jquake = prev.jquake; };
                }
              )
            ];
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              # Rename colliding existing files instead of failing activation
              # (e.g. ~/.config/user-dirs.dirs from xdg-user-dirs).
              backupFileExtension = "backup";
              extraSpecialArgs = { inherit inputs; };
              users.mitac = import ./home/mitac.nix;
            };
          }
        ];
      };
    };
}
