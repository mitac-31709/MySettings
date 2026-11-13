-- NixOS-friendly overrides for LazyVim.
-- Mason downloads non-Nix binaries that often fail without nix-ld; use
-- programs.neovim.extraPackages in home/programs.nix instead.
-- dev = false: these are not in the nix plugin dir. missing = false in
-- lazy setup means they are not cloned either.
return {
  { "mason-org/mason.nvim", enabled = false, dev = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false, dev = false },
  { "WhoIsSethDaniel/mason-tool-installer.nvim", enabled = false, dev = false },
  {
    "nvim-treesitter/nvim-treesitter",
    -- Parsers are parser/*.so in this directory (nix symlinkJoin).
    -- nvim-treesitter's get_installed() lists that directory, so LazyVim
    -- does not call TS.install for the languages it already finds.
    -- The directory is in the store: adding a language is a nix change,
    -- not a runtime compile.
    opts = {
      install_dir = vim.fn.stdpath("data") .. "/nix/treesitter",
    },
  },
}
