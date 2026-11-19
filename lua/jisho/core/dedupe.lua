local M = {}

local c = require('jisho.core.cache')
local s = require('jisho.core.search')

local sfmt = string.format
local strim = vim.trim
local slower = string.lower
local sgsub = string.gsub
local schar = string.char
local band = bit.band
local brshift = bit.rshift

local vnotif = vim.notify
local vlog = vim.log.levels
local vexpand = vim.fn.expand

local _key_memo = {}

local function clear_memo()
  _key_memo = {}
end

-- Hiragana -> katakana: U+3041..U+3096 and U+309D..U+309E map to +0x60.
-- Keyed by the 3-byte UTF-8 sequence so one gsub pass converts a word.
local _h2k = {}
local function u8(cp)
  return schar(0xE0 + brshift(cp, 12), 0x80 + band(brshift(cp, 6), 0x3F), 0x80 + band(cp, 0x3F))
end
for cp = 0x3041, 0x3096 do _h2k[u8(cp)] = u8(cp + 0x60) end
for cp = 0x309D, 0x309E do _h2k[u8(cp)] = u8(cp + 0x60) end

local function norm_kana(w)
  return (sgsub(w, '\227[\129\130][\128-\191]', _h2k))
end

local function get_key(w)
  local m = _key_memo[w]
  if m then return m end
  local n = sgsub(slower(strim(w)), '%s+', ' ')
  n = norm_kana(n)
  _key_memo[w] = n
  return n
end

function M.inspect_inflight()
  local cnt = 0
  local words = {}
  for w, d in pairs(c.in_flight) do
    cnt = cnt + 1
    words[#words + 1] = sfmt('%s (%d callbacks)', w, #d.callbacks)
  end
  if cnt == 0 then
    vnotif('No in-flight requests', vlog.INFO, { title = 'Jisho Dedupe' })
  else
    vnotif(sfmt('%d in-flight request(s):\n%s', cnt, table.concat(words, '\n')), vlog.INFO,
      { title = 'Jisho Dedupe', timeout = 5000 })
  end
end

function M.clear_inflight()
  local cnt = 0
  for w in pairs(c.in_flight) do
    c.in_flight[w] = nil
    cnt = cnt + 1
  end
  vnotif(sfmt('Cleared %d in-flight request(s)', cnt), vlog.INFO, { title = 'Jisho Dedupe' })
end

function M.check_cache_duplicate(w)
  local k = get_key(w)
  for cw in pairs(c.search_cache) do
    if get_key(cw) == k then return cw, c.search_cache[cw] end
  end
  return nil, nil
end

function M.clear_cache()
  -- In place: cache.lua saves its own reference to this table.
  local sc = c.search_cache
  for w in pairs(sc) do sc[w] = nil end
  clear_memo()
  c.save_cache()
  vnotif('Search cache cleared', vlog.INFO, { title = 'Jisho Dedupe' })
end

function M.refresh(w, cfg)
  if not w or w == '' then w = vexpand('<cword>') end
  w = sgsub(strim(w), '%s+', ' ')
  if not w or w == '' then
    vnotif('Please provide the Japanese word to query.', vlog.WARN)
    return
  end
  cfg = cfg or c.config
  local cc = c.search_cache[w]
  if cc then
    c.search_cache[w] = nil; c.save_cache()
  end
  local dw = M.check_cache_duplicate(w)
  if dw and dw ~= w then
    c.search_cache[dw] = nil; c.save_cache()
  end
  s.search(w, cfg)
end

M.get_key = get_key

return M
