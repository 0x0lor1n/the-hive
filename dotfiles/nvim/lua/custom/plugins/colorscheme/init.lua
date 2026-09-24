local highlight_overrides = require "custom.plugins.colorscheme.hl_overrides"
local palette = require "custom.plugins.colorscheme.palette"
local constants = require "custom.constants"

return {
  {
    "rebelot/kanagawa.nvim",
    -- same rev as bat.nix `kanagawaSrc`: one upstream for bat, delta and nvim
    commit = "bb85e4bfc8d89b0e62c8fa53ccdd13d12e2f77b3",
    lazy = false,
    priority = 1000,
    init = function()
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "kanagawa*",
        callback = function()
          -- upstream's black is sumiInk0; foot's (theme.nix ansi) is the editor bg
          vim.g.terminal_color_0 = "#1F1F28"
        end,
      })
    end,
    opts = {
      theme = "wave",
      background = { dark = "wave", light = "wave" },
      transparent = constants.transparent_background,
      commentStyle = { italic = false },
      keywordStyle = { italic = false },
      -- signs sit on the editor bg (hl_overrides paints SignColumn/LineNr with it)
      colors = { theme = { all = { ui = { bg_gutter = "none" } } } },
      overrides = function(colors)
        return highlight_overrides(palette.get(colors.palette))
      end,
    },
  },
}
