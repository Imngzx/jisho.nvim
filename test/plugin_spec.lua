-- Zero-config use: commands exist without loading the plugin, and nothing
-- needs setup() — the first use runs it, including the disk cache.
local h = dofile('test/helpers.lua')
local net = h.stub_net()

-- A cache file from an earlier session.
local file = vim.fn.stdpath('cache') .. '/jisho_cache.json'
vim.fn.mkdir(vim.fn.fnamemodify(file, ':h'), 'p')
vim.fn.writefile({ vim.json.encode({
  version = 1,
  cache = vim.empty_dict(),
  history = { { word = '昨日', timestamp = os.time() - 60 } },
}) }, file)

h.test('commands are defined without loading jisho', function()
  for _, name in ipairs({ 'Jisho', 'JishoHistory', 'JishoRefresh', 'JishoDedupe' }) do
    h.eq(2, vim.fn.exists(':' .. name), name)
  end
  h.eq(nil, package.loaded['jisho'], 'jisho not required')
end)

h.test(':JishoDedupe completes its subcommands', function()
  h.eq({ 'clear-inflight', 'clear-cache' }, vim.fn.getcompletion('JishoDedupe cl', 'cmdline'), 'cl')
end)

h.test(':JishoHistory without setup() shows the saved history', function()
  vim.cmd('JishoHistory')
  h.ok(h.wait_floats(1), 'history window')
  local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  h.ok(text:find('昨日', 1, true), 'saved entry listed')
end)

h.test(':JishoRefresh without setup() searches', function()
  vim.cmd('JishoRefresh 猫')
  h.ok(h.wait_floats(1), 'result window')
  h.eq(1, #net.calls, 'requests')
end)

h.test('setup() after first use keeps one copy of the history', function()
  require('jisho').setup({ layout = 'compact' })
  local n = 0
  local hist = require('jisho.core.cache').hist
  for i = 1, #hist do
    if hist[i].word == '昨日' then n = n + 1 end
  end
  h.eq(1, n, 'entries for 昨日')
  h.eq('compact', require('jisho').config.layout, 'option applied')
end)

h.finish()
