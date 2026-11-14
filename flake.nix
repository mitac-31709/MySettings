{
  description = "NixOS configuration for mitac (Sway + greetd, Chromebook delbin & VAIO)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Declarative age-encrypted secrets (decrypted at activation using Bitwarden-backed master key).
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Live systemd job tree on the boot console.
    # https://codeberg.org/wvhulle/bootvine/src/branch/main/docs/install.md
    bootvine = {
      url = "git+https://codeberg.org/wvhulle/bootvine";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # ChromeOS ALSA UCM overlays (sof-rt5682 etc. for volteer/delbin)
    alsa-ucm-conf-cros = {
      url = "github:WeirdTreeThing/alsa-ucm-conf-cros/standalone";
      flake = false;
    };
    # Fresher nixpkgs solely for Cursor packages (avoid bumping the whole system).
    # flake-update does not move this input; flake-update-cursor does.
    nixpkgs-cursor.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Vendor .debs (flake update re-fetches; see scripts/flake-update.sh).
    # Keep URL version in sync with uniclipboardVersion below (flake-update.sh).
    uniclipboard-deb = {
      url = "https://github.com/UniClipboard/UniClipboard/releases/download/v1.6.2/UniClipboard_1.6.2_amd64.deb";
      flake = false;
    };
    # Keep URL version in sync with chatgptVersion below (flake-update.sh).
    chatgpt-deb = {
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.1111.21308_amd64.deb";
      flake = false;
    };
    # Keep URL version in sync with grokBotVersion below (flake-update.sh).
    grok-bot-deb = {
      url = "https://downloads.cursor.com/grokbot/stable/83d46d618ef4c12afa17edd8e3c29d6caf046d17/linux/x64/grok-bot_1.1.0_amd64.deb";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      agenix,
      alsa-ucm-conf-cros,
      bootvine,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      # Must match inputs.uniclipboard-deb URL (updated by scripts/flake-update.sh).
      uniclipboardVersion = "1.6.2";
      # Must match inputs.chatgpt-deb URL (updated by scripts/flake-update.sh).
      chatgptVersion = "26.1111.21308";
      # Must match inputs.grok-bot-deb URL (updated by scripts/flake-update.sh).
      grokBotVersion = "1.1.0";

      mkHost =
        {
          flakeTarget,
          hostModule,
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs flakeTarget; };
          modules = [
            hostModule
            home-manager.nixosModules.home-manager
            agenix.nixosModules.default
            bootvine.nixosModules.default
            {
              # Links this generation to a git commit (shows in
              # `nixos-rebuild list-generations` / `nixos-version --json`).
              # Uncommitted trees get dirtyRev / dirtyShortRev; clean trees get rev.
              system.configurationRevision = self.rev or self.dirtyRev or "dirty";

              nixpkgs.config.allowUnfree = true;
              nixpkgs.overlays = [
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
                    inherit (cursorPkgs) cursor-cli;
                    # Cursor's resources/helpers/node is an unpatched FHS binary that
                    # SIGSEGVs under nix-ld on this host (dl_main / SEGV_ACCERR). MCP
                    # / npm-exec helpers then dump core. Point it at nixpkgs node.
                    code-cursor = cursorPkgs.code-cursor.overrideAttrs (old: {
                      postInstall = (old.postInstall or "") + ''
                        helperNode="$out/lib/cursor/resources/app/resources/helpers/node"
                        if [[ -e "$helperNode" ]]; then
                          rm -f "$helperNode"
                          ln -s ${final.nodejs}/bin/node "$helperNode"
                        fi
                      '';
                    });
                    uniclipboard = final.callPackage ./pkgs/uniclipboard {
                      src = inputs.uniclipboard-deb;
                      version = uniclipboardVersion;
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
                    # Left-bar AI status: hover slide-in chips (companion to waybar custom/ai).
                    ai-status-chips = final.callPackage ./pkgs/ai-status-chips { };
                    # Official Grok Bot Linux desktop (Cursor / x.ai).
                    grok-bot = final.callPackage ./pkgs/grok-bot {
                      src = inputs.grok-bot-deb;
                      version = grokBotVersion;
                    };
                    # 1.8.4 + Sway AWT / sounds / no-update-prompt wrapper.
                    jquake = final.callPackage ./pkgs/jquake { jquake = prev.jquake; };
                    # OpenCode 2 CLI (nixpkgs still ships 1.x; pin npm linux-x64 binary).
                    opencode = final.callPackage ./pkgs/opencode { };
                    # Google Antigravity CLI (`agy`; binary from antigravity-public).
                    antigravity = final.callPackage ./pkgs/antigravity { };
                  }
                )
              ];
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                # Rename colliding existing files instead of failing activation
                # (e.g. ~/.config/user-dirs.dirs from xdg-user-dirs).
                backupFileExtension = "backup";
                extraSpecialArgs = { inherit inputs flakeTarget; };
                users.mitac = import ./home/mitac.nix;
              };
            }
          ];
        };

      chromebook = mkHost {
        flakeTarget = "chromebook";
        hostModule = ./hosts/chromebook;
      };
    in
    {
      nixosConfigurations = {
        inherit chromebook;
        vaio = mkHost {
          flakeTarget = "vaio";
          hostModule = ./hosts/vaio;
        };
        # Legacy alias so existing `.#mitac` rebuild commands keep working.
        mitac = chromebook;
      };
    };
}
