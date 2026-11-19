-- Search status is one progress message: no :messages spam while running,
-- always closed with a final status, failures kept in history.
local h = dofile('test/helpers.lua')

local mode = { delay = 200, body = h.FIXTURE }
vim.net = {
  request = function(_, _, cb)
    local d = mode
    vim.defer_fn(function() cb(nil, { body = d.body }) end, d.delay)
  end,
}

local jisho = require('jisho')
jisho.setup({ use_snacks = false, use_budoux = false, notify = false })

local function messages(pat)
  local n = 0
  for _, l in ipairs(vim.split(vim.fn.execute('messages'), '\n')) do
    if l:find(pat, 1, true) then n = n + 1 end
  end
  return n
end

h.test('a search goes running -> success without filling :messages', function()
  vim.cmd('messages clear')
  h.progress = {}
  jisho.search('食べる')
  h.ok(h.wait_floats(1), 'window opened')
  h.drain()
  h.eq('running', h.progress[1].status, 'first update')
  h.eq('Searching: 食べる', h.progress[1].text, 'running text')
  h.eq({ status = 'success', text = '✓ 食べる' }, h.progress[#h.progress], 'last update')
  h.eq(2, #h.progress, 'updates (no animation frames)')
  h.eq(0, messages('Searching'), ':messages lines')
end)

h.test('a cache hit reports success without a request', function()
  h.progress = {}
  jisho.search('食べる')
  h.ok(h.wait_floats(1), 'window opened')
  h.drain()
  h.eq({ { status = 'success', text = '✓ 食べる (cached)' } }, h.progress, 'updates')
end)

h.test('a failure is closed as failed and kept in :messages', function()
  vim.cmd('messages clear')
  h.progress = {}
  mode = { delay = 10, body = vim.json.encode({ data = {} }) }
  jisho.search('zzzz')
  vim.wait(500, function() return h.last_progress('failed') ~= nil end)
  h.eq('✗ zzzz: Word not found', h.last_progress('failed'), 'failed text')
  h.eq(1, messages('zzzz: Word not found'), ':messages lines')
end)

h.test('an older search finishing late does not close a newer one', function()
  h.progress = {}
  mode = { delay = 300, body = h.FIXTURE }
  jisho.search('古い')
  mode = { delay = 600, body = h.FIXTURE }
  jisho.search('新しい')
  vim.wait(400)
  h.eq('running', h.progress[#h.progress].status, 'still running after the old one finished')
  h.ok(h.wait_floats(2), 'both windows')
  h.drain()
  h.eq({ status = 'success', text = '✓ 新しい' }, h.progress[#h.progress], 'closed by the newer search')
end)

h.finish()
