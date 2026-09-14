local M = {}

M.resolve = function(bufnr, do_warn)
  local lazy_core_utils = require "lazy.core.util"
  local lint = require "lint"
  local buf = bufnr or vim.api.nvim_get_current_buf()

  local names = lint._resolve_linter_by_ft(vim.bo.filetype)

  names = vim.list_extend({}, names)

  if #names == 0 then
    vim.list_extend(names, lint.linters_by_ft["_"] or {})
  end

  vim.list_extend(names, lint.linters_by_ft["*"] or {})

  local ctx = { filename = vim.api.nvim_buf_get_name(buf) }
  ctx.dirname = vim.fn.fnamemodify(ctx.filename, ":h")
  names = vim.tbl_filter(function(name)
    local linter = lint.linters[name]
    if do_warn and not linter then
      lazy_core_utils.warn("Linter not found: " .. name, { title = "nvim-lint" })
    end
    return linter and not (type(linter) == "table" and linter.condition and not linter.condition(ctx))
  end, names)

  return names
end

return M
