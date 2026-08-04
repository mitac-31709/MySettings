-- Basic options
vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 250
vim.opt.splitright = true
vim.opt.splitbelow = true

-- lazy.nvim bundled via Home Manager (xdg.dataFile)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
  -- ~/.config/nvim is a Home Manager symlink into the Nix store (read-only).
  lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",
  checker = {
    enabled = false, -- Nix manages lazy.nvim itself
  },
  change_detection = {
    notify = false,
  },
})
