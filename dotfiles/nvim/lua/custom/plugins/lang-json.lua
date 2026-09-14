local constants = require "custom.constants"

return {
  {
    enabled = not constants.first_install,
    import = "lazyvim.plugins.extras.lang.json",
  },

  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = {
      ensure_installed = {
        "json",
        "json5",
      },
    },
  },
}
