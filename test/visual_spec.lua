-- One mapping for Normal and Visual mode, and :Jisho with a range.
local h = dofile('test/helpers.lua')

local jisho = require('jisho')
jisho.setup({ use_snacks = false, use_budoux = false })
local core = require('jisho.core')
local got
core.search = function(w) got = w end

vim.keymap.set({ 'n', 'x' }, '<F2>', function() require('jisho').search() end)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'これは 食べる です', '二行目 second', 'third line' })

local function press(keys) vim.api.nvim_feedkeys(vim.keycode(keys), 'xt', false) end

h.test('Normal mode leaves the word to the core (<cword>)', function()
  got = false
  vim.api.nvim_win_set_cursor(0, { 2, 13 })
  press('<F2>')
  h.eq(nil, got, 'word passed')
end)

h.test('Visual mode looks up the selection and leaves Visual mode', function()
  got = nil
  vim.api.nvim_win_set_cursor(0, { 1, 10 })
  press('ve<F2>')
  h.eq('食べる', got, 'charwise selection')
  h.eq('n', vim.fn.mode(), 'mode after')
end)

h.test('a multi-line selection is joined with spaces', function()
  got = nil
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press('Vj<F2>')
  h.eq('これは 食べる です 二行目 second', got, 'linewise selection')
end)

h.test(":'<,'>Jisho looks up the last selection", function()
  got = nil
  vim.api.nvim_win_set_cursor(0, { 1, 10 })
  press('ve<Esc>')
  vim.cmd("'<,'>Jisho")
  h.eq('食べる', got, 'selection')
end)

h.test(':2,3Jisho looks up those lines', function()
  got = nil
  vim.cmd('2,3Jisho')
  h.eq('二行目 second third line', got, 'lines')
end)

h.test(':Jisho word ignores the range', function()
  got = nil
  vim.cmd('Jisho 猫')
  h.eq('猫', got, 'argument')
end)

h.test("a '<Cmd>Jisho<CR>' mapping covers both modes", function()
  vim.keymap.set({ 'n', 'x' }, '<F3>', '<Cmd>Jisho<CR>')
  got = false
  vim.api.nvim_win_set_cursor(0, { 2, 13 })
  press('<F3>')
  h.eq('', got, 'Normal mode: empty, the core uses <cword>')
  got = nil
  vim.api.nvim_win_set_cursor(0, { 1, 10 })
  press('ve<F3>')
  h.eq('食べる', got, 'Visual mode: the selection')
  h.eq('n', vim.fn.mode(), 'mode after')
end)

h.test("a ':Jisho<CR>' mapping covers both modes", function()
  vim.keymap.set({ 'n', 'x' }, '<F4>', ':Jisho<CR>')
  got = nil
  vim.api.nvim_win_set_cursor(0, { 1, 10 })
  press('ve<F4>')
  h.eq('食べる', got, "Visual mode becomes :'<,'>Jisho")
end)

h.finish()
