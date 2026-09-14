local keymaps_utils = require "custom.utils.keymaps"
local map = keymaps_utils.map

map("n", "<leader>m,l", function()
  local prev_l = vim.fn.getreg "l"
  local prev_ltype = vim.fn.getregtype "l"
  vim.fn.setreg("l", "EF/\0275\011rvE\"zyBi[\"zpa](Ea)")
  vim.cmd "normal! @l"
  vim.fn.setreg("l", prev_l, prev_ltype)
end, "markdown link", { noremap = true })

map("n", "<leader>m,i", function()
  local register_key = "i"
  local prev_register = vim.fn.getreg(register_key)
  local prev_register_type = vim.fn.getregtype(register_key)
  vim.fn.setreg(register_key, "^cwimportf=\0275vf(\0275cfrom AF\02750f)\0275C")
  vim.cmd("normal! @" .. register_key)
  vim.fn.setreg(register_key, prev_register, prev_register_type)
end, "require to import", { noremap = true })
