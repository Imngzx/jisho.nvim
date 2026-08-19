local M = {}

local c = require('jisho.core.cache')
local s = require('jisho.core.search')

local sfmt = string.format
local strim = vim.trim
local slower = string.lower
local ssub = string.sub
local sgsub = string.gsub

local vnotif = vim.notify
local vlog = vim.log.levels
local vexpand = vim.fn.expand

local _key_memo = {}

local function clear_memo()
  _key_memo = {}
end

local function norm_kana(w)
  local h2k = {
    ['あ'] = 'ア',
    ['い'] = 'イ',
    ['う'] = 'ウ',
    ['え'] = 'エ',
    ['お'] = 'オ',
    ['か'] = 'カ',
    ['き'] = 'キ',
    ['く'] = 'ク',
    ['け'] = 'ケ',
    ['こ'] = 'コ',
    ['さ'] = 'サ',
    ['し'] = 'シ',
    ['す'] = 'ス',
    ['せ'] = 'セ',
    ['そ'] = 'ソ',
    ['た'] = 'タ',
    ['ち'] = 'チ',
    ['つ'] = 'ツ',
    ['て'] = 'テ',
    ['と'] = 'ト',
    ['な'] = 'ナ',
    ['に'] = 'ニ',
    ['ぬ'] = 'ヌ',
    ['ね'] = 'ネ',
    ['の'] = 'ノ',
    ['は'] = 'ハ',
    ['ひ'] = 'ヒ',
    ['ふ'] = 'フ',
    ['へ'] = 'ヘ',
    ['ほ'] = 'ホ',
    ['ま'] = 'マ',
    ['み'] = 'ミ',
    ['む'] = 'ム',
    ['め'] = 'メ',
    ['も'] = 'モ',
    ['や'] = 'ヤ',
    ['ゆ'] = 'ユ',
    ['よ'] = 'ヨ',
    ['ら'] = 'ラ',
    ['り'] = 'リ',
    ['る'] = 'ル',
    ['れ'] = 'レ',
    ['ろ'] = 'ロ',
    ['わ'] = 'ワ',
    ['を'] = 'ヲ',
    ['ん'] = 'ン',
    ['が'] = 'ガ',
    ['ぎ'] = 'ギ',
    ['ぐ'] = 'グ',
    ['げ'] = 'ゲ',
    ['ご'] = 'ゴ',
    ['ざ'] = 'ザ',
    ['じ'] = 'ジ',
    ['ず'] = 'ズ',
    ['ぜ'] = 'ゼ',
    ['ぞ'] = 'ゾ',
    ['だ'] = 'ダ',
    ['ぢ'] = 'ヂ',
    ['づ'] = 'ヅ',
    ['で'] = 'デ',
    ['ど'] = 'ド',
    ['ば'] = 'バ',
    ['び'] = 'ビ',
    ['ぶ'] = 'ブ',
    ['べ'] = 'ベ',
    ['ぼ'] = 'ボ',
    ['ぱ'] = 'パ',
    ['ぴ'] = 'ピ',
    ['ぷ'] = 'プ',
    ['ぺ'] = 'ペ',
    ['ぽ'] = 'ポ',
    ['ゔ'] = 'ヴ',
    ['ゃ'] = 'ャ',
    ['ゅ'] = 'ュ',
    ['ょ'] = 'ョ',
    ['っ'] = 'ッ',
  }
  local res = ''
  for i = 1, #w do
    local ch = ssub(w, i, i)
    res = res .. (h2k[ch] or ch)
  end
  return res
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
  c.search_cache = {}
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

function M.setup_commands() end

return M
