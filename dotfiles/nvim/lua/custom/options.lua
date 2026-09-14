local constants = require "custom.constants"
local nvim_utils = require "custom.utils.nvim"
local icons_constants = require "custom.constants.icons"

vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.opt.termsync = false

vim.opt.number = true
vim.opt.numberwidth = 2
vim.opt.relativenumber = true

vim.opt.grepformat = "%f:%l:%c:%m"
vim.opt.grepprg = "rg --vimgrep"

vim.opt.jumpoptions = "stack,view"

vim.opt.confirm = true

vim.opt.mouse = "a"

vim.opt.statuscolumn = [[%!v:lua.require('custom.utils.statuscolumn').statuscolumn()]]

vim.opt.cmdheight = 0

vim.opt.laststatus = 3
vim.opt.statusline = "%#Normal#"
if not constants.in_kittyscrollback and not constants.in_vi_edit then
  vim.opt.statusline = [[%!v:lua.require('custom.utils.statusline').statusline()]]

  nvim_utils.autocmd("FileType", {
    group = nvim_utils.augroup "load_statusline_in_qf",
    pattern = "qf",
    callback = function()
      vim.opt_local.statusline = [[%!v:lua.require('custom.utils.statusline').statusline()]]
      vim.opt_local.signcolumn = "yes:1"
    end,
  })
end

-- global bufferline
vim.opt.showtabline = constants.in_fast and 0 or 2
vim.o.tabline = "%#Normal#"

vim.opt.foldmethod = "expr"
vim.opt.foldlevelstart = 99
vim.opt.foldnestmax = 10
vim.opt.foldenable = false
vim.opt.foldlevel = 99
vim.opt.foldcolumn = "0"
vim.opt.foldtext = "v:lua.require'custom.utils.folds'.foldtext()"

vim.opt.showmode = false

nvim_utils.autocmd("User", {
  group = nvim_utils.augroup "load_clipboard",
  pattern = "VeryLazy",
  callback = function()
    vim.opt.clipboard = vim.env.SSH_TTY and "" or "unnamedplus"
  end,
})

vim.opt.breakindent = false

vim.opt.undofile = true
vim.opt.undolevels = 10000

vim.opt.backup = false
vim.opt.writebackup = false

vim.opt.ignorecase = true
vim.opt.smartcase = true

vim.opt.signcolumn = "yes"

vim.opt.updatetime = 250
vim.opt.timeoutlen = 300

vim.opt.splitright = true
vim.opt.splitbelow = true

vim.opt.list = true
vim.opt.listchars = {
  tab = "󰌒 ",
  extends = "…",
  precedes = "…",
  trail = "·",
  nbsp = "󱁐",
}
vim.opt.fillchars = {
  eob = " ",
  diff = "╱",
  foldopen = "-",
  foldclose = "+",
  foldsep = " ",
  fold = " ",
}

vim.opt.inccommand = "nosplit"

vim.opt.cursorline = true
vim.opt.cursorcolumn = not constants.transparent_background

vim.opt.scrolloff = 4
vim.opt.sidescrolloff = 4

vim.opt.hlsearch = true

vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.shiftwidth = 2
vim.opt.smartindent = false
vim.opt.shiftround = true

vim.opt.virtualedit = "block"

vim.opt.formatoptions = "qjl1"

vim.opt.shortmess:append "sI"

vim.opt.shortmess:append "WcC"

vim.opt.termguicolors = true

vim.opt.compatible = false

vim.opt.pumheight = 15

vim.opt.pumblend = 0

vim.opt.splitkeep = "screen"

vim.opt.wrap = false

vim.opt.swapfile = false

vim.opt.autoread = true

vim.opt.smoothscroll = true

if not constants.in_neovide then
  vim.opt.guifont = "IosevkaTerm NF:h10"
end

if constants.in_neovide then
  vim.opt.shell = "zsh"
end

vim.opt.synmaxcol = 500

vim.opt.spell = false
vim.opt.spelllang = { "en_us", "es" }

vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "skiprtp", "folds" }

vim.opt.whichwrap:append "<>[]hl"

vim.opt.winborder = "none"
