-- Budoux `w` / `b` in the result window. Needs budoux.lua installed under
-- stdpath('data')/site/pack/*/{opt,start}/budoux.lua; skipped otherwise.
local h = dofile('test/helpers.lua')

local found = vim.fn.globpath(vim.fn.stdpath('data') .. '/site/pack', '*/*/budoux.lua', false, true)[1]
if not found then
  io.stdout:write('  skip  budoux.lua not installed\n')
  h.finish()
  return
end
vim.opt.rtp:append(found)

local ui = require('jisho.ui')
local CFG = { use_budoux = true, use_snacks = false, window = { width = 0.9, height = 0.5, border = 'none' } }
local LINES = {
  '## 食べる *( たべる )* `⭐ Common`',
  '  > 今日は天気がいいので散歩に行きました',
  '',
  'next line',
}

local function open()
  ui.open_window(LINES, 't', CFG)
end

local function at() return vim.api.nvim_win_get_cursor(0) end

local function press(keys) vim.api.nvim_feedkeys(keys, 'xt', false) end

--- Columns visited by pressing `key` n times from {row, col}.
local function walk(row, col, key, n)
  vim.api.nvim_win_set_cursor(0, { row, col })
  local out = {}
  for i = 1, n do
    press(key)
    local p = at()
    out[i] = p[1] .. ':' .. p[2]
  end
  return out
end

local function yank(keys, row, col)
  vim.api.nvim_win_set_cursor(0, { row, col })
  vim.fn.setreg('"', '')
  press(keys)
  return vim.fn.getreg('"')
end

h.test('w steps by Budoux phrase and never stops on a blank', function()
  open()
  -- 2:2 '>', 2:4 今日は, 2:13 天気が, 2:22 いいので, 2:34 散歩に, 2:43 行きました
  h.eq({ '2:2', '2:4', '2:13', '2:22', '2:34', '2:43' }, walk(2, 0, 'w', 6), 'w on line 2')
  h.eq({ '1:3', '1:13', '1:16', '1:26' }, walk(1, 0, 'w', 4), 'w on mixed header')
end)

h.test('w past the last phrase goes to the next line; an empty line is a stop', function()
  open()
  h.eq({ '3:0', '4:0' }, walk(2, 43, 'w', 2), 'w from 行きました')
end)

h.test('b walks back and crosses to the previous line', function()
  open()
  h.eq({ '2:34', '2:22', '2:13', '2:4', '2:2' }, walk(2, 43, 'b', 5), 'b on line 2')
  h.eq({ '2:43' }, walk(3, 0, 'b', 1), 'b from the empty line')
end)

h.test('a count repeats the motion', function()
  open()
  vim.api.nvim_win_set_cursor(0, { 2, 4 })
  press('3w')
  h.eq({ 2, 34 }, at(), '3w')
  press('2b')
  h.eq({ 2, 13 }, at(), '2b')
end)

h.test('w works as an operator motion and in visual mode', function()
  open()
  h.eq('今日は', yank('yw', 2, 4), 'yw')
  h.eq('今日は天気が', yank('y2w', 2, 4), 'y2w')
  h.eq('今日は天', yank('vwy', 2, 4), 'vwy (inclusive)')
  h.eq('行きました', yank('yw', 2, 43), 'yw on the last phrase stops at the line end')
end)

h.test('e / ge stop at Budoux phrase ends', function()
  open()
  -- 今日は ends 2:10, 天気が 2:19, いいので 2:31, 散歩に 2:40, 行きました 2:55
  h.eq({ '2:2', '2:10', '2:19', '2:31' }, walk(2, 0, 'e', 4), 'e on line 2')
  h.eq({ '2:40', '2:31', '2:19' }, walk(2, 55, 'ge', 3), 'ge on line 2')
  h.eq({ '4:3' }, walk(2, 55, 'e', 1), 'e skips the empty line')
  h.eq({ '3:0', '2:55' }, walk(4, 0, 'ge', 2), 'ge stops on the empty line')
end)

h.test('ye / yge are inclusive like Vim', function()
  open()
  h.eq('今日は', yank('ye', 2, 4), 'ye')
  h.eq('今日は天気が', yank('y2e', 2, 4), 'y2e')
  h.eq('で散', yank('yge', 2, 34), 'yge: back to the end of いいので')
end)

h.test('non-Japanese text matches the built-in motions exactly', function()
  local lines = {
    '- **1.** `[Noun]` café, cafe, coffeehouse',
    '  **Tags:** Food, cooking',
    '- **2.** `[Noun]` (combined) café and bar — one’s résumé…',
    '',
    '   ',
    '## ⭐ `JLPT-N5` ＡＢＣ　１２３ x_y foo.bar(baz)',
    'last word',
  }
  local function seq(keyfn, start)
    vim.api.nvim_win_set_cursor(0, start)
    local out, prev = {}, nil
    for _ = 1, 500 do
      keyfn()
      local p = at()
      local s = p[1] .. ':' .. p[2]
      if s == prev then break end
      out[#out + 1] = s
      prev = s
    end
    return out
  end
  local starts = { w = { 1, 0 }, e = { 1, 0 }, b = { #lines, 8 }, ge = { #lines, 8 } }
  local ref = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(ref)
  vim.api.nvim_buf_set_lines(ref, 0, -1, false, lines)
  vim.bo.filetype = 'markdown'
  local want = {}
  for k, st in pairs(starts) do want[k] = seq(function() vim.cmd('normal! ' .. k) end, st) end
  ui.open_window(lines, 't', CFG)
  for k, st in pairs(starts) do
    h.eq(want[k], seq(function() press(k) end, st), k)
  end
end)

h.test('ASCII-only lines keep Vim word stops', function()
  open()
  h.eq({ '4:5' }, walk(4, 0, 'w', 1), 'w on "next line"')
end)

h.test('closing a window frees its boundary cache', function()
  local function cache_size()
    local i = 1
    while true do
      local n, v = debug.getupvalue(ui.open_window, i)
      if not n then return nil end
      if n == 'setup_budoux' then
        local j = 1
        while true do
          local n2, v2 = debug.getupvalue(v, j)
          if not n2 then return nil end
          if n2 == 'budoux_cache' then return vim.tbl_count(v2) end
          j = j + 1
        end
      end
      i = i + 1
    end
  end
  h.close_floats()
  h.drain()
  local before = cache_size()
  for _ = 1, 20 do
    open()
    press('wq')
  end
  h.drain()
  h.eq(before, cache_size(), 'cache entries')
end)

h.finish()
