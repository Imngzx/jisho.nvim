-- Without vim.net.request the search goes through `curl`.
local h = dofile('test/helpers.lua')
local sys = h.stub_curl()

local jisho = require('jisho')
jisho.setup({ use_snacks = false, use_budoux = false })

h.test('curl fallback opens a window', function()
  jisho.search('食べる')
  h.ok(h.wait_floats(1), 'window opened')
  h.eq(1, #sys.calls, 'curl calls')
  local cmd = sys.calls[1]
  h.eq('curl', cmd[1], 'binary')
  h.ok(vim.tbl_contains(cmd, 'keyword=食べる'), 'keyword passed to --data-urlencode')
end)

h.finish()
