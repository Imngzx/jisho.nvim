---@class JishoWindowConfig
---@field width? number float width from 0.0. to 1.0, defautl is 0.6
---@field height? number float height from 0.0 to 1.0, default is 0.7
---@field border? string|"none"|"single"|"double"|"rounded"|"solid"|"shadow"

---@class JishoConfig
---@field use_snacks? boolean
---@field use_budoux? boolean
---@field layout? string|"compact"|"spacious"|"super_spacious"
---@field window? JishoWindowConfig

local M = {}

local vim_tbl_deep_extend = vim.tbl_deep_extend
local nvim_create_user_command = vim.api.nvim_create_user_command
local pcall = pcall

---@type JishoConfig
M.config = {
  use_snacks = pcall(require, 'snacks'),
  use_budoux = pcall(require, 'budoux'),
  layout = 'spacious',
  window = {
    width = 0.6,
    height = 0.7,
    border = 'rounded',
  },
}

---@param opts? JishoConfig
function M.setup(opts)
  M.config = vim_tbl_deep_extend('force', M.config, opts or {})
  require('jisho.core').setup(M.config)
end

function M.search(word)
  require('jisho.core').search(word, M.config)
end

function M.history()
  require('jisho.core').history()
end

local dedupe = require('jisho.core.dedupe')

dedupe.setup_commands()

nvim_create_user_command('Jisho', function(opts)
  require('jisho.core').search(opts.args, M.config)
end, { nargs = '*' })

nvim_create_user_command('JishoHistory', function()
  require('jisho.core').history()
end, {})

nvim_create_user_command('JishoDedupe', function(opts)
  local subcmd = opts.args
  if subcmd == 'inflight' then
    dedupe.inspect_inflight()
  elseif subcmd == 'clear-inflight' then
    dedupe.clear_inflight()
  elseif subcmd == 'clear-cache' then
    dedupe.clear_cache()
  elseif subcmd == 'refresh' then
    dedupe.refresh(opts.fargs[1], M.config)
  else
    vim.notify('Usage: JishoDedupe [inflight|clear-inflight|clear-cache|refresh <word>]', vim.log.levels.INFO, { title = 'Jisho Dedupe' })
  end
end, { nargs = '*', complete = function() return { 'inflight', 'clear-inflight', 'clear-cache', 'refresh' } end })

nvim_create_user_command('JishoRefresh', function(opts)
  dedupe.refresh(opts.args, M.config)
end, { nargs = '?' })

return M
