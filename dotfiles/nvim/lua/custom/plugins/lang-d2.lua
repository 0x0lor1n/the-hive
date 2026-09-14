return {
  {
    -- Neovim core has no *.d2 mapping, and d2.nvim only registers one from
    -- plugin/d2.lua -- which never runs, because both specs below lazy-load on
    -- `ft = "d2"`. Register it eagerly here so the filetype exists first.
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = function()
      vim.filetype.add {
        extension = {
          d2 = "d2",
        },
      }
    end,
  },
  {
    "ravsii/tree-sitter-d2",
    ft = "d2",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    build = "make nvim-install",
    config = function()
      require("tree-sitter-d2").setup()
    end,
  },
  {
    "kentchiu/d2.nvim",
    ft = "d2",
    config = function()
      require("d2").setup()
    end,
  },
}
