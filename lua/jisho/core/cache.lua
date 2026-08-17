local M = {}

local style = require('jisho.style')

local string_format = string.format
local string_byte = string.byte
local string_gsub = string.gsub
local string_upper = string.upper
local table_concat = table.concat
local math_min = math.min
local tostring = tostring
local pcall = pcall
local os_time = os.time
local uv = vim.uv
local io_open = io.open
local vim_fs_normalize = vim.fs.normalize

local vim_notify = vim.notify
local vim_schedule = vim.schedule
local vim_fn_expand = vim.fn.expand
local vim_trim = vim.trim
local vim_log_levels = vim.log.levels
local vim_json_decode = vim.json.decode
local vim_json_encode = vim.json.encode
local vim_net_request = vim.net and vim.net.request
local vim_system = vim.system
local vim_api = vim.api
local vim_bo = vim.bo
local vim_wo = vim.wo

-- Search cache: [normalized_word] = { lines = {...}, title = "...", timestamp = ..., word = "..." }
local search_cache = {}
local CACHE_TTL = 300 -- 5 minutes
local CACHE_FILE = vim_fs_normalize(vim.fn.stdpath('cache') .. '/jisho_cache.json')
local CACHE_VERSION = 1

-- In-flight request deduplication
local in_flight = {}

-- Spinner state
local spinner_frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local spinner_timer = nil
local spinner_notify_id = 'jisho_req'
local spinner_word = nil
local spinner_frame_idx = 1

-- History for :JishoHistory command
local search_history = {}
local MAX_HISTORY = 100

local function urlencode(str)
  if not str then return '' end
  return string_gsub(str, '([^\r\n%w %-%_%.%~])', function(c)
    if c == ' ' then return '+' end
    if c == '\n' then return '%0D%0A' end
    return string_format('%%%02X', string_byte(c))
  end)
end

local function load_cache()
  local f = io_open(CACHE_FILE, 'r')
  if not f then return end
  local content = f:read('*a')
  f:close()
  local ok, data = pcall(vim_json_decode, content)
  if ok and data and data.version == CACHE_VERSION then
    local now = os_time()
    for word, entry in pairs(data.cache or {}) do
      if (now - entry.timestamp) < CACHE_TTL then
        search_cache[word] = entry
      end
    end
    for _, entry in ipairs(data.history or {}) do
      table.insert(search_history, entry)
    end
  end
end

local function save_cache()
  vim_schedule(function()
    local cache_dir = vim_fs_normalize(vim.fn.stdpath('cache'))
    vim.fn.mkdir(cache_dir, 'p')
    local f = io_open(CACHE_FILE, 'w')
    if not f then return end
    local data = {
      version = CACHE_VERSION,
      cache = search_cache,
      history = search_history,
    }
    f:write(vim_json_encode(data))
    f:close()
  end)
end

local function add_to_history(word, timestamp)
  -- Remove existing entry for this word
  for i = #search_history, 1, -1 do
    if search_history[i].word == word then
      table.remove(search_history, i)
    end
  end
  -- Add to front
  table.insert(search_history, 1, { word = word, timestamp = timestamp })
  -- Trim
  while #search_history > MAX_HISTORY do
    table.remove(search_history)
  end
  save_cache()
end

local function start_spinner(word)
  spinner_word = word
  spinner_frame_idx = 1
  local frame = spinner_frames[1]
  vim_notify(frame .. ' Searching: ' .. word, vim_log_levels.INFO, { title = 'Jisho.org', id = spinner_notify_id })

  spinner_timer = uv.new_timer()
  spinner_timer:start(0, 80, function()
    vim_schedule(function()
      spinner_frame_idx = (spinner_frame_idx % #spinner_frames) + 1
      frame = spinner_frames[spinner_frame_idx]
      vim_notify(frame .. ' Searching: ' .. spinner_word, vim_log_levels.INFO, { title = 'Jisho.org', id = spinner_notify_id })
    end)
  end)
end

local function stop_spinner(success, word, err)
  if spinner_timer then
    spinner_timer:stop()
    spinner_timer:close()
    spinner_timer = nil
  end
  spinner_word = nil

  if success then
    vim_notify('✓ Query successful: ' .. word, vim_log_levels.INFO, { title = 'Jisho.org', id = spinner_notify_id, timeout = 10 })
  else
    vim_notify('✗ Search failed: ' .. word .. (err and (' - ' .. err) or ''), vim_log_levels.ERROR, { title = 'Jisho.org', id = spinner_notify_id })
  end
end

-- Export for other modules
M.search_cache = search_cache
M.CACHE_TTL = CACHE_TTL
M.CACHE_FILE = CACHE_FILE
M.CACHE_VERSION = CACHE_VERSION
M.in_flight = in_flight
M.spinner_frames = spinner_frames
M.spinner_timer = spinner_timer
M.spinner_notify_id = spinner_notify_id
M.spinner_word = spinner_word
M.spinner_frame_idx = spinner_frame_idx
M.search_history = search_history
M.MAX_HISTORY = MAX_HISTORY
M.urlencode = urlencode
M.load_cache = load_cache
M.save_cache = save_cache
M.add_to_history = add_to_history
M.start_spinner = start_spinner
M.stop_spinner = stop_spinner

-- Setup function
function M.setup(opts)
  M.config = opts or {}
  load_cache()
end

return M