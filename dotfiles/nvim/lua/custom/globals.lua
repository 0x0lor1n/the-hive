local constants = require "custom.constants"

if constants.in_nix then
  vim.env.PATH = "/run/current-system/sw/bin/:" .. vim.env.PATH
end

vim.env.GIT_EDITOR = "nvim"

vim.g.loaded_node_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

vim.g.matchparen_timeout = 2
vim.g.matchparen_insert_timeout = 2

if constants.disable_netrw then
  vim.g.loaded_netrw = 1
  vim.g.loaded_netrwPlugin = 1
end

if constants.in_neovide then
  vim.g.neovide_floating_shadow = false
  vim.g.neovide_hide_mouse_when_typing = true
  vim.g.neovide_floating_z_height = 7
  vim.g.neovide_floating_blur_amount_x = 0
  vim.g.neovide_floating_blur_amount_y = 0
end

_G.dd = function(...)
  Snacks.debug.inspect(...)
end
