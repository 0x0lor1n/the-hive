local constants = require "custom.constants"

-- ACPI ASL: no core mapping and no treesitter grammar; highlighted by
-- syntax/asl.vim (enabled via enable_filetypes_syntax in autocmds.lua).
vim.filetype.add {
  extension = {
    asl = "asl",
  },
}

if constants.in_fast then
  return {}
end

return {
  {
    -- Core filetypes already cover it: *.s/*.S/*.asm -> asm, *.nasm -> nasm,
    -- *.ld -> ld (linkerscript parser registers itself for `ld`).
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = {
      ensure_installed = { "asm", "nasm", "linkerscript", "objdump" },
    },
  },
  {
    "neovim/nvim-lspconfig",
    optional = true,
    opts = {
      servers = {
        -- From nixpkgs (home/dev/languages.nix). Dialect/arch come from a
        -- per-project .asm-lsp.toml (`asm-lsp gen-config`); default is GAS x86_64.
        asm_lsp = {
          mason = false,
          filetypes = { "asm", "nasm", "vmasm" },
        },
      },
    },
  },
}
