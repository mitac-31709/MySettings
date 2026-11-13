#!/usr/bin/env bash
# Move only inputs.nixpkgs-cursor (code-cursor / cursor-cli).
# nixpkgs and nixpkgs-cursor both track nixos-unstable. A full
# `nix flake update` pins them to the same commit, so Cursor cannot
# stay ahead of the system. This command updates that one input.
set -euo pipefail

if [[ $# -ge 1 && -f "${1}/flake.nix" ]]; then
  root=$1
else
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if [[ ! -f "$root/flake.nix" ]]; then
  echo "flake-update-cursor: checkout not found: $root" >&2
  exit 1
fi
cd "$root"
nix flake update nixpkgs-cursor
echo "nixpkgs-cursor updated. Review, commit, then rebuild."
