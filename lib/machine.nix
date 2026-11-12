# Machine-local paths. Edit here instead of scattering literals through modules.
# repoPath is the checkout nixos-rebuild and flake-update operate on.
# The script bodies are copied into the Nix store; they are not run from this tree.
{
  repoPath = "/home/mitac/MySettings";
  # nixosConfigurations.<flakeHost>
  flakeHost = "mitac";
}
