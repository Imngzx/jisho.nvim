-- Failure paths: a transport error and a word with no results must not
-- open a window, must not be cached, and must not leave an in-flight entry.
local h = dofile('test/helpers.lua')

local mode = { err = nil, body = nil }
local calls = 0
vim.net = {
  request = function(_, _, cb)
    calls = calls + 1
    vim.defer_fn(function()
      if mode.err then cb(mode.err, nil) else cb(nil, { body = mode.body }) end
    end, 10)
  end,
}

local jisho = require('jisho')
jisho.setup({ use_snacks = false, use_budoux = false, notify = false })
local c = require('jisho.core.cache')

local function last_error() return h.last_progress('failed') end

h.test('a transport error reports and caches nothing', function()
  mode.err = 'timeout'
  jisho.search('犬')
  vim.wait(500, function() return last_error() ~= nil end)
  h.ok((last_error() or ''):find('timeout', 1, true), 'error notified')
  h.eq(0, h.float_count(), 'no window')
  h.eq(nil, c.search_cache['犬'], 'not cached')
  h.eq(nil, c.in_flight['犬'], 'in-flight cleared')
end)

h.test('no results reports "Word not found"', function()
  h.progress = {}
  mode.err, mode.body = nil, vim.json.encode({ data = {} })
  jisho.search('zzzz')
  vim.wait(500, function() return last_error() ~= nil end)
  h.ok((last_error() or ''):find('Word not found', 1, true), 'not-found notified')
  h.eq(0, h.float_count(), 'no window')
end)

h.test('a failed word is fetched again next time', function()
  local before = calls
  mode.body = h.FIXTURE
  jisho.search('犬')
  h.ok(h.wait_floats(1), 'window opened')
  h.eq(before + 1, calls, 'new request')
end)

h.finish()
