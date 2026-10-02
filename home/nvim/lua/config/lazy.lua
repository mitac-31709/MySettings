-- lazy.nvim is bundled via Home Manager (outside lazy's managed plugin root).
local lazypath = vim.fn.stdpath("data") .. "/nix/lazy.nvim"
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
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
  },
  -- ~/.config/nvim is a Home Manager symlink into the Nix store (read-only).
  lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = false, -- Nix manages lazy.nvim itself; plugins update via :Lazy
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
