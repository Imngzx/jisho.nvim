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

nvim_create_user_command('Jisho', function(opts)
  require('jisho.core').search(opts.args, M.config)
end, { nargs = '*' })

nvim_create_user_command('JishoHistory', function()
  require('jisho.core').history()
end, {})

return M
