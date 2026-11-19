-- Without vim.net.request the search goes through `curl`.
local h = dofile('test/helpers.lua')
local sys = h.stub_curl()

local jisho = require('jisho')
jisho.setup({ use_snacks = false, use_budoux = false, notify = false, timeout = 150 })

h.test('curl fallback opens a window', function()
  jisho.search('食べる')
  h.ok(h.wait_floats(1), 'window opened')
  h.eq(1, #sys.calls, 'curl calls')
  local cmd = sys.calls[1]
  h.eq('curl', cmd[1], 'binary')
  h.ok(vim.tbl_contains(cmd, 'keyword=食べる'), 'keyword passed to --data-urlencode')
  local i = vim.fn.index(cmd, '--max-time')
  h.ok(i >= 0, '--max-time passed')
  h.eq('1', cmd[i + 2], '--max-time rounds the timeout up to whole seconds')
end)

h.test('a hung curl is killed at the timeout', function()
  sys.hang = true
  jisho.search('猫')
  vim.wait(1000, function() return h.last_progress('failed') ~= nil end)
  h.eq('✗ 猫: Timed out after 0.15 s', h.last_progress('failed'), 'failed text')
  h.eq(15, sys.killed, 'SIGTERM sent')
end)

h.finish()
