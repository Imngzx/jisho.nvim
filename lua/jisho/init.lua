---@class JishoWindowConfig
---@field width? number float width from 0.0. to 1.0, defautl is 0.6
---@field height? number float height from 0.0 to 1.0, default is 0.7
---@field border? string|"none"|"single"|"double"|"rounded"|"solid"|"shadow"

---@class JishoConfig
---@field use_snacks? boolean
---@field window? JishoWindowConfig

local M = {}

---@type JishoConfig
M.config = {
  use_snacks = pcall(require, 'snacks'),
  window = {
    width = 0.6,
    height = 0.7,
    border = "rounded",
  },
}

---@param opts? JishoConfig
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_create_user_command('Jisho', function(cmd_opts)
    require('jisho.core').search(cmd_opts.args, M.config)
  end, { nargs = '?' })
end

return M
