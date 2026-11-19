-- A request that never answers is killed after `timeout`, reported, and does
-- not block the next search for the same word.
local h = dofile('test/helpers.lua')

local hang = true
local closed = 0
local calls = 0
vim.net = {
  request = function(_, _, cb)
    calls = calls + 1
    if not hang then
      vim.defer_fn(function() cb(nil, { body = h.FIXTURE }) end, 10)
      return { close = function() end }
    end
    return {
      close = function()
        closed = closed + 1
        -- vim.net reports a killed request through the callback, late.
        vim.defer_fn(function() cb('Request killed with signal 15', nil) end, 20)
      end,
    }
  end,
}

local jisho = require('jisho')
jisho.setup({ use_snacks = false, use_budoux = false, notify = false, timeout = 150 })
local c = require('jisho.core.cache')

h.test('a hung request times out', function()
  jisho.search('犬')
  vim.wait(1000, function() return h.last_progress('failed') ~= nil end)
  h.eq('✗ 犬: Timed out after 0.15 s', h.last_progress('failed'), 'failed text')
  h.eq(1, closed, 'request closed')
  h.eq(nil, c.in_flight['犬'], 'in-flight entry cleared')
  h.eq(0, h.float_count(), 'no window')
end)

h.test('the late kill callback changes nothing', function()
  h.progress = {}
  h.drain(100)
  h.eq({}, h.progress, 'no further updates')
end)

h.test('the same word can be searched again', function()
  hang = false
  jisho.search('犬')
  h.ok(h.wait_floats(1), 'window opened')
  h.eq(2, calls, 'new request')
end)

h.finish()
