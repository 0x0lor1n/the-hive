local nvim_utils = require "custom.utils.nvim"

local M = {}

local current_git_branch = ""
local current_git_dir = ""
local branch_cache = {}
local active_bufnr = "0"
local sep = package.config:sub(1, 1)
local file_changed = sep ~= "\\" and vim.uv.new_fs_event() or vim.uv.new_fs_poll()
local git_dir_cache = {}

local function get_git_head(head_file)
  local f_head = io.open(head_file)
  if f_head then
    local HEAD = f_head:read()
    f_head:close()
    local branch = HEAD:match "ref: refs/heads/(.+)$"
    if branch then
      current_git_branch = branch
    else
      current_git_branch = HEAD:sub(1, 6)
    end
  end
  return nil
end

local function update_branch()
  active_bufnr = tostring(vim.api.nvim_get_current_buf())
  file_changed:stop()
  local git_dir = current_git_dir
  if git_dir and #git_dir > 0 then
    local head_file = git_dir .. sep .. "HEAD"
    get_git_head(head_file)
    file_changed:start(
      head_file,
      sep ~= "\\" and {} or 1000,
      vim.schedule_wrap(function()
        update_branch()
      end)
    )
  else
    current_git_branch = ""
  end
  branch_cache[vim.api.nvim_get_current_buf()] = current_git_branch
end

local function update_current_git_dir(git_dir)
  if current_git_dir ~= git_dir then
    current_git_dir = git_dir
    update_branch()
  end
end

function M.find_git_dir(dir_path)
  local git_dir = vim.env.GIT_DIR
  if git_dir then
    update_current_git_dir(git_dir)
    return git_dir
  end

  local file_dir = dir_path or vim.fn.expand "%:p:h"

  if package.loaded.oil then
    local oil = require "oil"
    local ok, dir = pcall(oil.get_current_dir)
    if ok and dir and dir ~= "" then
      file_dir = vim.fn.fnamemodify(dir, ":p:h")
    end
  end

  if file_dir and file_dir:match "term://.*" then
    file_dir = vim.fn.expand(file_dir:gsub("term://(.+)//.+", "%1"))
  end

  local root_dir = file_dir
  while root_dir do
    if git_dir_cache[root_dir] then
      git_dir = git_dir_cache[root_dir]
      break
    end
    local git_path = root_dir .. sep .. ".git"
    local git_file_stat = vim.uv.fs_stat(git_path)
    if git_file_stat then
      if git_file_stat.type == "directory" then
        git_dir = git_path
      elseif git_file_stat.type == "file" then
        local file = io.open(git_path)
        if file then
          git_dir = file:read()
          git_dir = git_dir and git_dir:match "gitdir: (.+)$"
          file:close()
        end
        if git_dir and git_dir:sub(1, 1) ~= sep and not git_dir:match "^%a:.*$" then
          git_dir = git_path:match "(.*).git" .. git_dir
        end
      end
      if git_dir then
        local head_file_stat = vim.uv.fs_stat(git_dir .. sep .. "HEAD")
        if head_file_stat and head_file_stat.type == "file" then
          break
        else
          git_dir = nil
        end
      end
    end
    root_dir = root_dir:match("(.*)" .. sep .. ".-")
  end

  git_dir_cache[file_dir] = git_dir
  if dir_path == nil then
    update_current_git_dir(git_dir)
  end
  return git_dir
end

function M.init()
  M.find_git_dir()
  nvim_utils.autocmd("BufEnter", {
    group = nvim_utils.augroup "git_branch",
    callback = function()
      M.find_git_dir()
    end,
  })
end
function M.get_branch(bufnr)
  if vim.g.actual_curbuf ~= nil and active_bufnr ~= vim.g.actual_curbuf then
    M.find_git_dir()
  end
  if bufnr then
    return branch_cache[bufnr] or ""
  end
  return current_git_branch
end

return M
