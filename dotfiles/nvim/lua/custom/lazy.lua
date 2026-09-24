local constants = require "custom.constants"
local lazy_utils = require "custom.utils.lazy"
local lazyvim_utils = require "custom.utils.lazyvim"
local lang_utils = require "custom.utils.lang"

lazy_utils.install()

lazy_utils.load_mappings()

-- Load `LazyVim` if possible
lazyvim_utils.install()

require("lazy").setup {
  spec = {
    {
      "folke/lazy.nvim",
      version = "*",
    },
    lazy_utils.find_local_nolazy_spec() or {},
    {
      "LazyVim/LazyVim",
      lazy = false,
      version = false,
      commit = lazyvim_utils.lazyvim_commit,
      priority = 10000,
      config = function() end,
    },
    {
      "folke/snacks.nvim",
      priority = 1000,
      lazy = false,
      opts = {},
      config = function(_, opts)
        local notify = vim.notify
        require("snacks").setup(opts)
        if lazy_utils.has "noice.nvim" then
          vim.notify = notify
        end
      end,
    },

    { import = "custom.plugins" },
  },
  defaults = {
    lazy = true,
    version = false,
  },
  dev = {
    path = vim.fn.stdpath "config" .. "/lua",
  },
  ui = {
    size = {
      width = constants.width_fullscreen,
      height = constants.height_fullscreen,
    },
  },
  install = { colorscheme = { "kanagawa", "habamax" } },
  checker = { enabled = true, notify = false },
  change_detection = { enabled = false },
  performance = {
    rtp = {
      disabled_plugins = lang_utils.list_merge({
        "2html_plugin",
        "bugreport",
        "compiler",
        "ftplugin",
        "getscript",
        "getscriptPlugin",
        "gzip",
        "logipat",
        "matchparen",
        "optwin",
        "rplugin",
        "rrhelper",
        "synmenu",
        "tar",
        "tarPlugin",
        "tohtml",
        "tutor",
        "vimball",
        "vimballPlugin",
        "zip",
        "zipPlugin",
      }, constants.disable_netrw and {
        "netrw",
        "netrwFileHandlers",
        "netrwPlugin",
        "netrwSettings",
      } or {}),
    },
  },
}
