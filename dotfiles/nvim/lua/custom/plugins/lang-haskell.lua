local constants = require "custom.constants"

return {
  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = {
      ensure_installed = { "haskell" },
    },
  },

  {
    "mrcjkb/haskell-tools.nvim",
    enabled = not constants.first_install,
    version = "^4",
    lazy = false,
    ft = { "haskell", "lhaskell", "cabal", "cabalproject" },
    dependencies = {
      "nvim-telescope/telescope.nvim",
      -- required by tools.repl.handler = "toggleterm" below; without it
      -- opening any .hs file throws from haskell-tools/deps.lua
      { "akinsho/toggleterm.nvim", version = "*", opts = {} },
    },
    config = function()
      local ht = require "haskell-tools"

      vim.g.haskell_tools = {
        hls = {
          on_attach = function(client, bufnr)
            local opts = { buffer = bufnr }
            vim.keymap.set("n", "<leader>lh", ht.hoogle.hoogle_signature, vim.tbl_extend("force", opts, { desc = "Hoogle Signature" }))
            vim.keymap.set("n", "<leader>le", ht.lsp.buf_eval_all, vim.tbl_extend("force", opts, { desc = "Evaluate All" }))
            vim.keymap.set("n", "<leader>lr", ht.repl.toggle, vim.tbl_extend("force", opts, { desc = "Toggle REPL (package)" }))
            vim.keymap.set("n", "<leader>lR", function()
              ht.repl.toggle(vim.api.nvim_buf_get_name(0))
            end, vim.tbl_extend("force", opts, { desc = "Toggle REPL (buffer)" }))
            vim.keymap.set("n", "<leader>lq", ht.repl.quit, vim.tbl_extend("force", opts, { desc = "Quit REPL" }))
          end,
        },
        tools = {
          repl = {
            handler = "toggleterm",
          },
          hover = {
            enable = true,
          },
        },
      }
    end,
  },

  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        haskell = { "ormolu" },
      },
    },
  },
}
