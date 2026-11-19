-- With a notifier plugin (vim.notify replaced) the status is an animated
-- spinner notification; with the built-in vim.notify a progress message.
local h = dofile('test/helpers.lua')
local net = h.stub_net({ delay = 300 })

local jisho = require('jisho')
jisho.setup({ use_snacks = false, use_budoux = false })
local c = require('jisho.core.cache')

local builtin = h.builtin_notify

h.test('auto: a replaced vim.notify means a notifier plugin', function()
  h.eq(true, c.use_notify(), 'recorder installed')
  local recorder = vim.notify
  vim.notify = builtin
  local ok = c.use_notify()
  vim.notify = recorder
  h.eq(false, ok, 'built-in vim.notify')
end)

h.test('notifier: spinner frames replace each other, then success', function()
  h.notes = {}
  h.progress = {}
  jisho.search('食べる')
  h.ok(h.wait_floats(1), 'window opened')
  h.drain()
  local frames = 0
  for i = 1, #h.notes - 1 do
    h.ok(h.notes[i].msg:find('Searching: 食べる', 1, true), 'frame text')
    frames = frames + 1
  end
  h.ok(frames >= 3, 'animated (got ' .. frames .. ' frames)')
  h.eq('✓ Query successful: 食べる', h.notes[#h.notes].msg, 'final')
  h.eq({}, h.progress, 'no progress message')
end)

h.test('notifier: the spinner stops after the search', function()
  local n = #h.notes
  vim.wait(300)
  h.eq(n, #h.notes, 'no frames after the result')
end)

h.test('notifier: a cache hit notifies "(cached)"', function()
  h.notes = {}
  jisho.search('食べる')
  h.drain()
  h.eq('✓ Query successful (cached): 食べる', h.notes[#h.notes].msg, 'cached')
  h.eq(1, #net.calls, 'no request')
end)

h.test('notify = false forces the progress message', function()
  jisho.setup({ notify = false })
  h.notes = {}
  h.progress = {}
  jisho.search('猫')
  h.ok(h.wait_floats(1), 'window opened')
  h.drain()
  h.eq({}, h.notes, 'no notifications')
  h.eq({ status = 'success', text = '✓ 猫' }, h.progress[#h.progress], 'progress')
end)

h.finish()
