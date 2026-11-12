# LazyVim's core specs, built from nixpkgs instead of cloned at nvim startup.
# Directory names are lazy.nvim's plugin.name (the repo, or the spec's `name`).
# Treesitter parsers are a separate runtime dir: nvim-treesitter main looks in
# `install_dir/parser`, not in the plugin tree. See home/nvim/lua/plugins/nix.lua.
{ pkgs, lib }:
let
  plugins = {
    "LazyVim" = pkgs.vimPlugins.LazyVim;
    "lazy.nvim" = pkgs.vimPlugins.lazy-nvim;
    "lazydev.nvim" = pkgs.vimPlugins.lazydev-nvim;
    "ts-comments.nvim" = pkgs.vimPlugins.ts-comments-nvim;
    "mini.ai" = pkgs.vimPlugins.mini-ai;
    "mini.pairs" = pkgs.vimPlugins.mini-pairs;
    "mini.icons" = pkgs.vimPlugins.mini-icons;
    "bufferline.nvim" = pkgs.vimPlugins.bufferline-nvim;
    # spec sets `name = "catppuccin"` (the repo name is just "nvim").
    "catppuccin" = pkgs.vimPlugins.catppuccin-nvim;
    "tokyonight.nvim" = pkgs.vimPlugins.tokyonight-nvim;
    "flash.nvim" = pkgs.vimPlugins.flash-nvim;
    "todo-comments.nvim" = pkgs.vimPlugins.todo-comments-nvim;
    "trouble.nvim" = pkgs.vimPlugins.trouble-nvim;
    "which-key.nvim" = pkgs.vimPlugins.which-key-nvim;
    "gitsigns.nvim" = pkgs.vimPlugins.gitsigns-nvim;
    "grug-far.nvim" = pkgs.vimPlugins.grug-far-nvim;
    "conform.nvim" = pkgs.vimPlugins.conform-nvim;
    "snacks.nvim" = pkgs.vimPlugins.snacks-nvim;
    "nvim-lint" = pkgs.vimPlugins.nvim-lint;
    # mason*.nvim is disabled in lua/plugins/nix.lua (dev = false) and is not
    # linked here. LSP binaries are programs.neovim.extraPackages.
    "nvim-lspconfig" = pkgs.vimPlugins.nvim-lspconfig;
    "nvim-treesitter" = pkgs.vimPlugins.nvim-treesitter;
    "nvim-treesitter-textobjects" = pkgs.vimPlugins.nvim-treesitter-textobjects;
    "nvim-ts-autotag" = pkgs.vimPlugins.nvim-ts-autotag;
    "noice.nvim" = pkgs.vimPlugins.noice-nvim;
    "nui.nvim" = pkgs.vimPlugins.nui-nvim;
    "lualine.nvim" = pkgs.vimPlugins.lualine-nvim;
    "persistence.nvim" = pkgs.vimPlugins.persistence-nvim;
    "plenary.nvim" = pkgs.vimPlugins.plenary-nvim;
  };

  # LazyVim's default ensure_installed, plus nix and typst (this repo's docs).
  # Queries stay inside the nvim-treesitter plugin; this dir is parser/*.so.
  treesitterGrammars = pkgs.vimPlugins.nvim-treesitter.withPlugins (p: [
    p.bash
    p.c
    p.diff
    p.html
    p.javascript
    p.jsdoc
    p.json
    p.lua
    p.luadoc
    p.luap
    p.markdown
    p.markdown_inline
    p.nix
    p.printf
    p.python
    p.query
    p.regex
    p.toml
    p.tsx
    p.typescript
    p.typst
    p.vim
    p.vimdoc
    p.xml
    p.yaml
  ]);
in
{
  plugins = pkgs.linkFarm "lazyvim-plugins" (
    lib.mapAttrsToList (name: path: {
      inherit name path;
    }) plugins
  );
  treesitter = pkgs.symlinkJoin {
    name = "nvim-treesitter-parsers";
    paths = treesitterGrammars.dependencies;
  };
}
