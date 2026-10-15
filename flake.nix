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
    sendanywhere-deb = {
      url = "https://update.send-anywhere.com/linux_downloads/sendanywhere_latest_amd64.deb";
      flake = false;
    };
    # Keep URL version in sync with uniclipboardVersion below (flake-update.sh).
    uniclipboard-deb = {
      url = "https://github.com/UniClipboard/UniClipboard/releases/download/v1.0.1/UniClipboard_1.0.1_amd64.deb";
      flake = false;
    };
    # Keep URL version in sync with chatgptVersion below (flake-update.sh).
    chatgpt-deb = {
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1002.52244_amd64.deb";
      flake = false;
    };
    # Keep URL version in sync with grokBotVersion below (flake-update.sh).
    grok-bot-deb = {
      url = "https://downloads.cursor.com/grokbot/stable/52da656f56d317510ca65ad6af3d69a2cde461e0/linux/x64/grok-bot_0.70.2_amd64.deb";
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
      uniclipboardVersion = "1.0.1";
      # Must match inputs.chatgpt-deb URL (updated by scripts/flake-update.sh).
      chatgptVersion = "26.1002.52244";
      # Must match inputs.grok-bot-deb URL (updated by scripts/flake-update.sh).
      grokBotVersion = "0.70.2";
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
                  sendanywhere = final.callPackage ./pkgs/sendanywhere {
                    src = inputs.sendanywhere-deb;
                  };
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
                  # Official Grok Bot Linux desktop (Cursor / x.ai).
                  grok-bot = final.callPackage ./pkgs/grok-bot {
                    src = inputs.grok-bot-deb;
                    version = grokBotVersion;
                  };
                  nodejs-official = final.callPackage ./pkgs/nodejs-official { };
                  deepseek-harness = final.callPackage ./pkgs/deepseek-harness { };
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
