-- Search flow over a stubbed vim.net.request: rendering, cache hit,
-- in-flight dedupe, errors, persistence.
local h = dofile('test/helpers.lua')
local net = h.stub_net({ delay = 50 })

local jisho = require('jisho')
jisho.setup({ use_snacks = false, use_budoux = false })
local c = require('jisho.core.cache')

h.test('a search opens one window with the rendered entry', function()
  jisho.search('食べる')
  h.ok(h.wait_floats(1), 'window opened')
  h.eq(1, #net.calls, 'requests')
  h.ok(net.calls[1]:find('keyword=%E9%A3%9F%E3%81%B9%E3%82%8B', 1, true), 'url-encoded keyword')
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  h.eq('## 食べる *( たべる )* `⭐ Common` `JLPT-N5`', lines[1], 'header')
  h.ok(vim.tbl_contains(lines, '**Other forms:** 喰べる *( たべる )*'), 'other forms')
  h.ok(vim.tbl_contains(lines, '- **1.** `[Ichidan verb]` to eat'), 'sense 1')
  h.ok(vim.tbl_contains(lines, '  **See also:** 食う'), 'see also')
end)

h.test('the same word again is a cache hit', function()
  jisho.search('  食べる  ')
  h.ok(h.wait_floats(1), 'window opened')
  h.eq(1, #net.calls, 'no new request')
end)

h.test('two searches in flight share one request', function()
  jisho.search('猫')
  jisho.search('猫')
  h.ok(h.wait_floats(2), 'two windows')
  h.eq(2, #net.calls, 'one new request')
  h.eq(nil, c.in_flight['猫'], 'in-flight entry cleared')
end)

h.test('results and history are saved to disk', function()
  h.drain()
  local d = assert(h.read_cache_file(), 'cache file written')
  h.ok(d.cache['食べる'] and d.cache['猫'], 'both words cached')
  h.eq('猫', d.history[1].word, 'newest history entry first')
end)

h.test('history keeps one entry per word', function()
  local n = 0
  for i = 1, #c.hist do
    if c.hist[i].word == '食べる' then n = n + 1 end
  end
  h.eq(1, n, 'entries for 食べる')
end)

h.finish()
