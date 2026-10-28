-- Show dotfiles by default in explorer / file find / grep.
-- Toggle still works: H (explorer), Alt-h (pickers).
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = { hidden = true },
          files = { hidden = true },
          grep = { hidden = true },
        },
      },
    },
  },
}
