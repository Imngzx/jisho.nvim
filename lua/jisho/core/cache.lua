local M = {}

local sfmt = string.format
local sbyte = string.byte
local sgsub = string.gsub
local schar = string.char
local pcall = pcall
local otime = os.time
local uv = vim.uv
local iopen = io.open
local vfn = vim.fn
local vfsn = vim.fs.normalize
local vnotif = vim.notify
local vsched = vim.schedule
local vlog = vim.log.levels
local vjson_dec = vim.json.decode
local vjson_enc = vim.json.encode

local _url_map = {}
for i = 0, 255 do
  local c = schar(i)
  if c:match('[%w%-_%.~]') then
    _url_map[i] = c
  elseif c == ' ' then
    _url_map[i] = '+'
  elseif c == '\n' then
    _url_map[i] = '%0D%0A'
  else
    _url_map[i] = sfmt('%%%02X', i)
  end
end

local function urlencode(str)
  if not str then return '' end
  return sgsub(str, '.', function(c)
    return _url_map[sbyte(c)]
  end)
end

local search_cache = {}
local CACHE_TTL = 300
local CACHE_FILE = vfsn(vfn.stdpath('cache') .. '/jisho_cache.json')
local CACHE_VER = 1

local in_flight = {}

local spin_frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local spin_timer = nil
local spin_id = 'jisho_req'
local spin_word = nil
local spin_idx = 1

local hist = {}
local MAX_HIST = 100

local function load_cache()
  local f = iopen(CACHE_FILE, 'r')
  if not f then return end
  local ok, data = pcall(vjson_dec, f:read('*a'))
  f:close()
  if not (ok and data and data.version == CACHE_VER) then return end
  local now = otime()
  local dc = data.cache
  if dc then
    for w, e in pairs(dc) do
      if (now - e.timestamp) < CACHE_TTL then
        search_cache[w] = e
      end
    end
  end
  local dh = data.history
  if dh then
    for i = 1, #dh do
      hist[#hist + 1] = dh[i]
    end
  end
end

local function save_cache()
  vsched(function()
    local dir = vfsn(vfn.stdpath('cache'))
    vfn.mkdir(dir, 'p')
    local f = iopen(CACHE_FILE, 'w')
    if not f then return end
    f:write(vjson_enc({ version = CACHE_VER, cache = search_cache, history = hist },
      { indent = '  ' }))
    f:close()
  end)
end

local function add_hist(w, ts)
  for i = #hist, 1, -1 do
    if hist[i].word == w then
      table.remove(hist, i)
      break
    end
  end
  table.insert(hist, 1, { word = w, timestamp = ts })
  if #hist > MAX_HIST then hist[MAX_HIST + 1] = nil end
  save_cache()
end

local function start_spin(w)
  spin_word = w
  spin_idx = 1
  spin_timer = uv.new_timer()
  spin_timer:start(0, 80, function()
    spin_idx = (spin_idx % 10) + 1
    vsched(function()
      vnotif(spin_frames[spin_idx] .. ' Searching: ' .. spin_word, vlog.INFO,
        { title = 'Jisho.org', id = spin_id })
    end)
  end)
end

local function stop_spin(ok, w, err)
  if spin_timer then
    spin_timer:stop()
    spin_timer:close()
    spin_timer = nil
  end
  spin_word = nil
  vsched(function()
    if ok then
      vnotif('✓ Query successful: ' .. w, vlog.INFO,
        { title = 'Jisho.org', id = spin_id, timeout = 10 })
    else
      vnotif('✗ Search failed: ' .. w .. (err and (' - ' .. err) or ''), vlog.ERROR,
        { title = 'Jisho.org', id = spin_id })
    end
  end)
end

M.search_cache = search_cache
M.CACHE_TTL = CACHE_TTL
M.CACHE_FILE = CACHE_FILE
M.CACHE_VER = CACHE_VER
M.in_flight = in_flight
M.spin_frames = spin_frames
M.spin_timer = spin_timer
M.spin_id = spin_id
M.spin_word = spin_word
M.spin_idx = spin_idx
M.hist = hist
M.MAX_HIST = MAX_HIST
M.urlencode = urlencode
M.load_cache = load_cache
M.save_cache = save_cache
M.add_hist = add_hist
M.start_spin = start_spin
M.stop_spin = stop_spin

function M.setup(opts)
  M.config = opts or {}
  load_cache()
end

return M
