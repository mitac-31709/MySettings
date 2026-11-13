# Machine-local paths. Edit here instead of scattering literals through modules.
# repoPath is the checkout nixos-rebuild and flake-update operate on.
# The script bodies are copied into the Nix store; they are not run from this tree.
{
  repoPath = "/home/mitac/MySettings";
  # Fallback nixosConfigurations.<flakeHost> when flakeTarget is not passed.
  flakeHost = "chromebook";
  # Proprietary Hiragino OTFs (not in git). Included only with --impure
  # when this directory exists; otherwise fontconfig uses Noto CJK.
  hiraginoDir = "/home/mitac/Documents/hiragino-otf";
}
