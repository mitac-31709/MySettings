-- lazy.nvim and the LazyVim plugin set are Home Manager links into the
-- Nix store (home/lazy-plugins.nix). dev.path is outside lazy's clone root
-- so the symlinks are not treated as "not installed".
local data = vim.fn.stdpath("data")
local lazypath = data .. "/nix/lazy.nvim"
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    lazy = false,
    -- Versions are the nixpkgs pins. A git tag here would fight dev.path.
    version = false,
  },
  -- Match github.com in the clone URL so every core spec uses the nix dir.
  -- fallback is off: a missing directory is a nix set problem, not a clone.
  dev = {
    path = data .. "/nix/plugins",
    patterns = { "github.com" },
    fallback = false,
  },
  -- Do not clone on startup. :Lazy update still records only non-local plugins.
  install = {
    missing = false,
    colorscheme = { "tokyonight", "habamax" },
  },
  -- ~/.config/nvim is a Home Manager symlink into the Nix store (read-only).
  -- Nix plugins are local, so this file does not pin them.
  lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",
  checker = {
    enabled = false,
    notify = false,
  },
  change_detection = {
    notify = false,
  },
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
