local constants = require "custom.constants"

-- Inline images (markdown/html previews, `:e foo.png`) over DEC sixel: foot
-- renders sixel natively, no kitty graphics protocol needed. Snacks.image only
-- speaks kitty, so it stays silent under foot and this plugin owns rendering.
-- ImageMagick with sixel output comes from homeModules/neovim.nix; tmux must
-- have allow-passthrough on (tmux/config.conf) or the DCS never reaches foot.
return {
  {
    "3rd/image.nvim",
    enabled = not constants.in_fast and not constants.in_neovide,
    event = "VeryLazy",
    opts = {
      backend = "sixel",
      processor = "magick_cli",
      -- Sixel is slow and the terminal clears it on any scroll; popup at the
      -- cursor is the mode the backend author calls usable.
      only_render_image_at_cursor = true,
      only_render_image_at_cursor_mode = "popup",
      max_width_window_percentage = 80,
      max_height_window_percentage = 60,
      window_overlap_clear_enabled = true,
      hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" },
      integrations = {
        markdown = {
          enabled = true,
          clear_in_insert_mode = true,
          download_remote_images = false,
          only_render_image_at_cursor = true,
          filetypes = { "markdown", "vimwiki" },
        },
        html = { enabled = true },
        neorg = { enabled = false },
        typst = { enabled = true },
      },
    },
  },
}
