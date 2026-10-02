-- NixOS-friendly overrides for LazyVim.
-- Mason downloads non-Nix binaries that often fail without nix-ld; use
-- programs.neovim.extraPackages in home/programs.nix instead.
return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "WhoIsSethDaniel/mason-tool-installer.nvim", enabled = false },
}
