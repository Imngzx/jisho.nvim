local M = {}

local cache = require('jisho.core.cache')
local search = require('jisho.core.search')

local string_format = string.format
local vim_notify = vim.notify
local vim_log_levels = vim.log.levels

-- Cache key memoization
local _cache_key_memo = {}

local function clear_cache_key_memo()
  _cache_key_memo = {}
end

-- ============================================================
-- Feature 1: Inspect/Clear In-Flight Requests
-- ============================================================

function M.inspect_inflight()
  local count = 0
  local words = {}
  vim.iter(pairs(cache.in_flight)):each(function(word, data)
    count = count + 1
    words[#words + 1] = string_format('%s (%d callbacks)', word, #data.callbacks)
  end)
  if count == 0 then
    vim_notify('No in-flight requests', vim_log_levels.INFO, { title = 'Jisho Dedupe' })
  else
    local msg = string_format('%d in-flight request(s):\n%s', count, table.concat(words, '\n'))
    vim_notify(msg, vim_log_levels.INFO, { title = 'Jisho Dedupe', timeout = 5000 })
  end
end

function M.clear_inflight()
  local count = 0
  vim.iter(pairs(cache.in_flight)):each(function(word)
    cache.in_flight[word] = nil
    count = count + 1
  end)
  vim_notify(string_format('Cleared %d in-flight request(s)', count), vim_log_levels.INFO, { title = 'Jisho Dedupe' })
end

-- ============================================================
-- Feature 2: Cache Deduplication (normalize similar words)
-- ============================================================

local function normalize_kana(word)
  -- Convert hiragana to katakana for comparison
  -- Since utf8 library may not be available, use string-based approach
  local hiragana_to_katakana = {
    ['あ']='ア', ['い']='イ', ['う']='ウ', ['え']='エ', ['お']='オ',
    ['か']='カ', ['き']='キ', ['く']='ク', ['け']='ケ', ['こ']='コ',
    ['さ']='サ', ['し']='シ', ['す']='ス', ['せ']='セ', ['そ']='ソ',
    ['た']='タ', ['ち']='チ', ['つ']='ツ', ['て']='テ', ['と']='ト',
    ['な']='ナ', ['に']='ニ', ['ぬ']='ヌ', ['ね']='ネ', ['の']='ノ',
    ['は']='ハ', ['ひ']='ヒ', ['ふ']='フ', ['へ']='ヘ', ['ほ']='ホ',
    ['ま']='マ', ['み']='ミ', ['む']='ム', ['め']='メ', ['も']='モ',
    ['や']='ヤ', ['ゆ']='ユ', ['よ']='ヨ',
    ['ら']='ラ', ['り']='リ', ['る']='ル', ['れ']='レ', ['ろ']='ロ',
    ['わ']='ワ', ['を']='ヲ', ['ん']='ン',
    ['が']='ガ', ['ぎ']='ギ', ['ぐ']='グ', ['げ']='ゲ', ['ご']='ゴ',
    ['ざ']='ザ', ['じ']='ジ', ['ず']='ズ', ['ぜ']='ゼ', ['ぞ']='ゾ',
    ['だ']='ダ', ['ぢ']='ヂ', ['づ']='ヅ', ['で']='デ', ['ど']='ド',
    ['ば']='バ', ['び']='ビ', ['ぶ']='ブ', ['べ']='ベ', ['ぼ']='ボ',
    ['ぱ']='パ', ['ぴ']='ピ', ['ぷ']='プ', ['ぺ']='ペ', ['ぽ']='ポ',
    ['ゔ']='ヴ',
    ['ゃ']='ャ', ['ゅ']='ュ', ['ょ']='ョ',
    ['っ']='ッ',
  }
  local result = ''
  for i = 1, #word do
    local c = word:sub(i, i)
    result = result .. (hiragana_to_katakana[c] or c)
  end
  return result
end

local function get_cache_key(word)
  local cached = _cache_key_memo[word]
  if cached then return cached end
  -- Normalize: lowercase, trim, collapse spaces, normalize kana
  local normalized = string.lower(vim.trim(word))
  normalized = string.gsub(normalized, '%s+', ' ')
  normalized = normalize_kana(normalized)
  _cache_key_memo[word] = normalized
  return normalized
end

function M.check_cache_duplicate(word)
  local key = get_cache_key(word)
  local result = vim.iter(pairs(cache.search_cache)):find(function(cached_word)
    return get_cache_key(cached_word) == key
  end)
  if result then
    return result, cache.search_cache[result]
  end
  return nil, nil
end

function M.clear_cache()
  cache.search_cache = {}
  clear_cache_key_memo()
  cache.save_cache()
  vim_notify('Search cache cleared', vim_log_levels.INFO, { title = 'Jisho Dedupe' })
end

-- ============================================================
-- Feature 3: Force Refresh Command
-- ============================================================

function M.refresh(word, config)
  word = word or vim.fn.expand('<cword>')
  word = string.gsub(vim.trim(word), '%s+', ' ')

  if not word or word == '' then
    vim_notify('Please provide the Japanese word to query.', vim_log_levels.WARN)
    return
  end

  config = config or cache.config

  -- Remove from cache if exists
  local cached = cache.search_cache[word]
  if cached then
    cache.search_cache[word] = nil
    cache.save_cache()
  end

  -- Also check for kana-normalized duplicates
  local dup_word, _ = M.check_cache_duplicate(word)
  if dup_word and dup_word ~= word then
    cache.search_cache[dup_word] = nil
    cache.save_cache()
  end

  -- Force new search (bypasses cache check)
  search.search(word, config)
end

-- ============================================================
-- User Commands
-- ============================================================

function M.setup_commands()
  -- No-op, commands are registered in init.lua
end

return M