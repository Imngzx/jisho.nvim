---@class JishoWindowConfig
---@field width? number float width from 0.0. to 1.0, defautl is 0.6
---@field height? number float height from 0.0 to 1.0, default is 0.7
---@field border? string|"none"|"single"|"double"|"rounded"|"solid"|"shadow"

---@class JishoConfig
---@field use_snacks? boolean
---@field use_budoux? boolean
---@field layout? string|"compact"|"spacious"|"super_spacious"
---@field timeout? integer request timeout in ms (default 10000)
---@field notify? boolean search status as a spinner notification (true) or a progress message (false); default: spinner when a notifier plugin replaced vim.notify
---@field window? JishoWindowConfig

local M = {}

local vim_tbl_deep_extend = vim.tbl_deep_extend
local pcall = pcall
local table_concat = table.concat
local vim_fn = vim.fn
local vim_keycode = vim.keycode
local nvim_feedkeys = vim.api.nvim_feedkeys
local nvim_buf_get_lines = vim.api.nvim_buf_get_lines

---@type JishoConfig
M.config = {
  use_snacks = pcall(require, 'snacks'),
  use_budoux = pcall(require, 'budoux'),
  layout = 'spacious',
  timeout = 10000,
  window = {
    width = 0.6,
    height = 0.7,
    border = 'rounded',
  },
}

local did_setup = false

--- Optional: the first search, command or history call runs it with the
--- defaults. Calling it again merges the new options.
---@param opts? JishoConfig
function M.setup(opts)
  M.config = vim_tbl_deep_extend('force', M.config, opts or {})
  require('jisho.core').setup(M.config)
  did_setup = true
end

local function ensure_setup()
  if not did_setup then M.setup() end
end

-- The selection as one string, joined with spaces across lines.
local function region(p1, p2, mode)
  return table_concat(vim_fn.getregion(p1, p2, { type = mode }), ' ')
end

--- Look up `word`. Without one: the selection in Visual mode, else the word
--- under the cursor, so one mapping covers both:
--- `vim.keymap.set({ 'n', 'x' }, '<leader>tj', function() require('jisho').search() end)`
---@param word? string
function M.search(word)
  ensure_setup()
  if word == nil or word == '' then
    local mode = vim_fn.mode()
    if mode == 'v' or mode == 'V' or mode == '\22' then
      word = region(vim_fn.getpos('v'), vim_fn.getpos('.'), mode)
      nvim_feedkeys(vim_keycode('<Esc>'), 'n', false)
    end
  end
  require('jisho.core').search(word, M.config)
end

function M.history()
  ensure_setup()
  require('jisho.core').history(M.config)
end

--- Look up `word` again, bypassing the cache.
---@param word? string
function M.refresh(word)
  ensure_setup()
  require('jisho.core.dedupe').refresh(word, M.config)
end

-- Command handlers, called from plugin/jisho.lua -----------------------------

--- :Jisho [word]. With a range and no word: `:'<,'>Jisho` looks up the last
--- selection, any other range the text of those lines.
---@param opts { args: string, fargs: string[], range: integer, line1: integer, line2: integer }
function M._cmd_jisho(opts)
  local word = opts.args
  if word == '' and opts.range > 0 then
    local p1, p2 = vim_fn.getpos("'<"), vim_fn.getpos("'>")
    if p1[2] == opts.line1 and p2[2] == opts.line2 then
      word = region(p1, p2, vim_fn.visualmode())
    else
      word = table_concat(nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false), ' ')
    end
  end
  M.search(word)
end

---@param opts { args: string, fargs: string[], range: integer, line1: integer, line2: integer }
function M._cmd_dedupe(opts)
  ensure_setup()
  local dedupe = require('jisho.core.dedupe')
  local sub = opts.fargs[1]
  if sub == 'inflight' then
    dedupe.inspect_inflight()
  elseif sub == 'clear-inflight' then
    dedupe.clear_inflight()
  elseif sub == 'clear-cache' then
    dedupe.clear_cache()
  elseif sub == 'refresh' then
    M.refresh(opts.fargs[2])
  else
    vim.notify('Usage: JishoDedupe [inflight|clear-inflight|clear-cache|refresh <word>]',
      vim.log.levels.INFO, { title = 'Jisho Dedupe' })
  end
end

return M
