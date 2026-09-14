return {
  {
    -- Neovim core already maps *.liq to the `liquidsoap` filetype, and
    -- treesitter.lua's FileType autocmd calls vim.treesitter.start() for any
    -- installed parser, so pulling the grammar in is all highlighting needs.
    -- Grammar is savonet/tree-sitter-liquidsoap (nvim-treesitter tier 2).
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = {
      ensure_installed = {
        "liquidsoap",
      },
    },
  },
}
