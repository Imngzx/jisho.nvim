local M = {}

M.config = {
  use_snacks = pcall(require, 'snacks'),

  -- 窗口通用配置
  window = {
    width = 0.6,
    height = 0.7,
    border = "rounded",
  },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

function M.search(word)
  require("jisho.core").search(word, M.config)
end

return M
