local constants = require "custom.constants"

return {
  {
    enabled = not constants.first_install,
    import = "lazyvim.plugins.extras.lang.sql",
  },
  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = {
      ensure_installed = {
        "sql",
      },
    },
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters = {
        sqlfluff = {
          require_cwd = false,
        },
      },
    },
  },
}
