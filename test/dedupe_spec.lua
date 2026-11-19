-- :JishoDedupe / :JishoRefresh and the normalized lookup key.
local h = dofile('test/helpers.lua')
local net = h.stub_net()

local jisho = require('jisho')
jisho.setup({ use_snacks = false, use_budoux = false })
local c = require('jisho.core.cache')
local d = require('jisho.core.dedupe')

h.test('get_key folds hiragana to katakana', function()
  h.eq('タベル', d.get_key('たべる'), 'plain')
  h.eq('ガギグゲゴパピプペポ', d.get_key('がぎぐげごぱぴぷぺぽ'), 'voiced')
  h.eq('ャュョッァヴヽヾ', d.get_key('ゃゅょっぁゔゝゞ'), 'small, ゔ, iteration marks')
  h.eq('タベル', d.get_key('タベル'), 'katakana unchanged')
  h.eq('食ベル', d.get_key('食べる'), 'kanji kept, okurigana folded')
end)

h.test('get_key lowercases and collapses whitespace', function()
  h.eq('hello world', d.get_key('  Hello \t World '), 'ascii')
  h.eq('ー・「」', d.get_key('ー・「」'), 'non-kana symbols in the same block untouched')
end)

h.test(':JishoDedupe clear-cache empties memory and disk', function()
  jisho.search('食べる')
  h.ok(h.wait_floats(1), 'window opened')
  h.drain()
  h.ok(h.read_cache_file().cache['食べる'], 'cached on disk first')

  vim.cmd('JishoDedupe clear-cache')
  h.drain()
  h.eq(nil, next(c.search_cache), 'memory cache empty')
  h.eq(0, vim.tbl_count(h.read_cache_file().cache), 'disk cache empty')
end)

h.test('after clear-cache the word is fetched again', function()
  h.close_floats()
  local before = #net.calls
  jisho.search('食べる')
  h.ok(h.wait_floats(1), 'window opened')
  h.eq(before + 1, #net.calls, 'new request')
end)

h.test(':JishoRefresh drops the katakana spelling of a cached hiragana word', function()
  h.close_floats()
  jisho.search('タベル')
  h.ok(h.wait_floats(1), 'window opened')
  h.close_floats()
  h.ok(c.search_cache['タベル'], 'katakana cached')
  local before = #net.calls
  vim.cmd('JishoRefresh たべる')
  h.ok(h.wait_floats(1), 'window opened')
  h.eq(nil, c.search_cache['タベル'], 'katakana entry dropped')
  h.eq(before + 1, #net.calls, 'refetched')
end)

h.finish()
