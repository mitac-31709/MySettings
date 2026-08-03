{
  description = "NixOS configuration for mitac (multi-session: Sway/Plasma/Hyprland, Chromebook delbin)";

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
    # Caelestia shell with animated/video wallpaper support
    caelestia-cli-aw = {
      url = "github:AdiAmbassador/caelestia-cli-aw";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    caelestia-shell-aw = {
      url = "github:AdiAmbassador/caelestia-shell-aw";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.caelestia-cli.follows = "caelestia-cli-aw";
    };
    # end-4 Quickshell fork (illogical-impulse inspired)
    end4-pc = {
      url = "github:pctrade/end4-pC";
      flake = false;
    };
    # Illogical Impulse Hyprland configs (required by end4-pC for startup/keybinds)
    dots-hyprland = {
      url = "github:end-4/dots-hyprland/aed4d1ec63f584905c28d2a678db5845579fdafc";
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
