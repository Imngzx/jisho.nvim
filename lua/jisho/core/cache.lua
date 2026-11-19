local M = {}

local sfmt = string.format
local sbyte = string.byte
local sgsub = string.gsub
local schar = string.char
local pcall = pcall
local otime = os.time
local iopen = io.open
local vfn = vim.fn
local vfsn = vim.fs.normalize
local vsched = vim.schedule
local vlog = vim.log.levels
local vjson_dec = vim.json.decode
local vjson_enc = vim.json.encode
local nvim_echo = vim.api.nvim_echo
local sfind = string.find
local dgetinfo = debug.getinfo
local type = type

local vasync_run
local vasync_sleep

local function ensure_async()
  if not vasync_run then
    vasync_run = vim.async.run
    vasync_sleep = vim.async.sleep
  end
end

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

-- Search status, two ways (`notify` option, default: auto):
-- * a notifier plugin replaced vim.notify (snacks, noice, nvim-notify) ->
--   an animated spinner notification, replaced in place through its `id`;
-- * built-in vim.notify -> one progress message (|progress-message|): the
--   built-in one ignores `id`, so a spinner would add a line to :messages
--   on every frame.
local spin_frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local SPIN_ID = 'jisho_req'
local PROGRESS_ID = 'jisho.search'
local spin_epoch = 0

local function use_notify()
  local opt = M.config and M.config.notify
  if opt ~= nil then return opt end
  local fn = vim.notify
  if type(fn) ~= 'function' then return false end
  return not sfind(dgetinfo(fn, 'S').source, 'vim/_core/editor', 1, true)
end

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

-- Scheduled: callers run in fast-event contexts, where nvim_echo is not
-- allowed. pcall: the progress fields need a recent Neovim.
---@param status 'running'|'success'|'failed'
---@param text string
---@param history boolean add to :messages (failures only)
local function progress(status, text, history)
  vsched(function()
    pcall(nvim_echo, { { text } }, history, {
      id = PROGRESS_ID,
      kind = 'progress',
      status = status,
      err = status == 'failed',
      title = 'Jisho',
      source = 'jisho',
    })
  end)
end

-- vim.notify is looked up on every call, not localized: a notifier plugin
-- may replace it after this module has loaded.

-- Returns the epoch of this search; only the search holding the current
-- epoch may close the status, so an older search finishing late cannot
-- overwrite a newer one that is still running.
local function start_spin(w)
  spin_epoch = spin_epoch + 1
  local epoch = spin_epoch
  if not use_notify() then
    progress('running', 'Searching: ' .. w, false)
    return epoch
  end
  ensure_async()
  vasync_run(function()
    local spin_idx = 1
    while epoch == spin_epoch do
      vim.notify(spin_frames[spin_idx] .. ' Searching: ' .. w, vlog.INFO,
        { title = 'Jisho.org', id = SPIN_ID })
      spin_idx = (spin_idx % 10) + 1
      vasync_sleep(80)
    end
  end)
  return epoch
end

local function stop_spin(ok, w, err, epoch)
  local current = epoch == spin_epoch
  if current then spin_epoch = spin_epoch + 1 end
  if use_notify() then
    vsched(function()
      if ok then
        if current then
          vim.notify('✓ Query successful: ' .. w, vlog.INFO,
            { title = 'Jisho.org', id = SPIN_ID, timeout = 10 })
        end
      else
        -- Not current: a newer search owns the spinner id, use a fresh one.
        vim.notify('✗ Search failed: ' .. w .. (err and (' - ' .. err) or ''), vlog.ERROR,
          { title = 'Jisho.org', id = current and SPIN_ID or nil })
      end
    end)
    return
  end
  if ok then
    if current then progress('success', '✓ ' .. w, false) end
    return
  end
  local msg = '✗ ' .. w .. (err and (': ' .. err) or '')
  if current then
    progress('failed', msg, true)
  else
    vsched(function() vim.notify(msg, vlog.ERROR, { title = 'Jisho' }) end)
  end
end

-- A cache hit: no request, just the result.
local function report_cached(w)
  if use_notify() then
    vsched(function()
      vim.notify('✓ Query successful (cached): ' .. w, vlog.INFO,
        { title = 'Jisho.org', id = SPIN_ID, timeout = 10 })
    end)
  else
    progress('success', '✓ ' .. w .. ' (cached)', false)
  end
end

M.search_cache = search_cache
M.CACHE_TTL = CACHE_TTL
M.CACHE_FILE = CACHE_FILE
M.CACHE_VER = CACHE_VER
M.in_flight = in_flight
M.hist = hist
M.MAX_HIST = MAX_HIST
M.urlencode = urlencode
M.load_cache = load_cache
M.save_cache = save_cache
M.add_hist = add_hist
M.start_spin = start_spin
M.stop_spin = stop_spin
M.progress = progress
M.report_cached = report_cached
M.use_notify = use_notify

local loaded = false

-- Called by every jisho.setup(); the disk cache is read only the first time,
-- or the history would be appended again.
function M.setup(opts)
  M.config = opts or {}
  if loaded then return end
  loaded = true
  load_cache()
end

return M
