local lazy_utils = require "custom.utils.lazy"
local highlight_overrides = require "custom.plugins.colorscheme.hl_overrides"
local constants = require "custom.constants"

-- Read Catppuccin configuration from environment variables
local flavor = os.getenv("CATPPUCCIN_FLAVOR") or "mocha"
local accent = os.getenv("CATPPUCCIN_ACCENT") or "mauve"

-- Validate flavor (fallback to mocha if invalid)
local valid_flavors = { latte = true, frappe = true, macchiato = true, mocha = true }
if not valid_flavors[flavor] then
  flavor = "mocha"
end

-- Validate accent (fallback to mauve if invalid)
local valid_accents = {
  rosewater = true, flamingo = true, pink = true, mauve = true,
  red = true, maroon = true, peach = true, yellow = true,
  green = true, teal = true, sky = true, sapphire = true,
  blue = true, lavender = true
}
if not valid_accents[accent] then
  accent = "mauve"
end

return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    event = "LazyFile",
    init = function()
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "catppuccin*",
        callback = function()
          lazy_utils.on_load("catppuccin", function()
            local C = require("catppuccin.palettes").get_palette()

            -- TODO: add custom colors for latte
            vim.g.terminal_color_0 = C.surface1
            vim.g.terminal_color_1 = C.red
            vim.g.terminal_color_2 = C.green
            vim.g.terminal_color_3 = C.yellow
            vim.g.terminal_color_4 = C.blue
            vim.g.terminal_color_5 = C.pink
            vim.g.terminal_color_6 = C.teal
            vim.g.terminal_color_7 = C.subtext1
            vim.g.terminal_color_8 = C.surface2
            vim.g.terminal_color_9 = C.red
            vim.g.terminal_color_10 = C.green
            vim.g.terminal_color_11 = C.yellow
            vim.g.terminal_color_12 = C.blue
            vim.g.terminal_color_13 = C.pink
            vim.g.terminal_color_14 = C.teal
            vim.g.terminal_color_15 = C.subtext0
          end)
        end,
      })
    end,
    opts = {
      flavour = flavor, -- Use environment variable
      background = {
        light = "latte",
        dark = "mocha",
      },
      transparent_background = constants.transparent_background,
      term_colors = false,
      dim_inactive = {
        enabled = false,
      },
      no_italic = true,
      no_bold = false,
      no_underline = false,
      styles = {
        comments = {},
        conditionals = {},
        loops = {},
        functions = {},
        keywords = {},
        strings = {},
        variables = {},
        numbers = {},
        booleans = {},
        properties = {},
        types = {},
        operators = {},
      },
      color_overrides = {
        all = {
          dark_purple = "#c7a0dc",
          sun = "#ffe9b6",
          vibrant_green = "#b6f4be",
        },
      },
      -- TODO: use custom_highlights
      custom_highlights = {},
      highlight_overrides = highlight_overrides,
      default_integrations = false,
      integrations = {
        -- enable the ones we'll use
        blink_cmp = true,
        diffview = true,
        fidget = true,
        flash = true,
        gitsigns = true,
        grug_far = true,
        harpoon = true,
        -- markdown = true,
        markview = true,
        mason = true,
        mini = {
          enabled = true,
          indentscope_color = accent,
        },
        neotree = true,
        noice = true,
        neotest = true,
        dap = true,
        dap_ui = true,
        native_lsp = {
          enabled = true,
          virtual_text = {
            errors = {},
            hints = {},
            warnings = {},
            information = {},
            ok = {},
          },
          underlines = {
            errors = { "undercurl" },
            hints = { "undercurl" },
            warnings = { "undercurl" },
            information = { "undercurl" },
            ok = { "undercurl" },
          },
          inlay_hints = {
            background = false,
          },
        },
        semantic_tokens = true,
        treesitter_context = true,
        treesitter = true,
        window_picker = true,
        rainbow_delimiters = true,
        render_markdown = true,
        snacks = {
          enabled = true,
          indent_scope_color = accent,
        },
        lsp_trouble = true,
        which_key = true,
      },
    },
  },
}
