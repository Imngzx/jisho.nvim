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
  vim_notify(frame .. ' Searching: ' .. word, vim_log_levels.INFO,
    { title = 'Jisho.org', id = spinner_notify_id })

  spinner_timer = uv.new_timer()
  spinner_timer:start(0, 80, function()
    vim_schedule(function()
      spinner_frame_idx = (spinner_frame_idx % #spinner_frames) + 1
      frame = spinner_frames[spinner_frame_idx]
      vim_notify(frame .. ' Searching: ' .. spinner_word, vim_log_levels.INFO,
        { title = 'Jisho.org', id = spinner_notify_id })
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
    vim_notify('✓ Query successful: ' .. word, vim_log_levels.INFO,
      { title = 'Jisho.org', id = spinner_notify_id, timeout = 10 })
  else
    vim_notify('✗ Search failed: ' .. word .. (err and (' - ' .. err) or ''), vim_log_levels.ERROR,
      { title = 'Jisho.org', id = spinner_notify_id })
  end
end

local function build_lines(item, config)
  local lines = {}
  local jp_list = item.japanese or {}
  local spacer = style.spacer
  local layout = config.layout

  -- Main word + other forms
  local main_jp = jp_list[1] or {}
  local word_jp = main_jp.word or main_jp.reading or 'Unknown'
  local reading = (main_jp.word and main_jp.reading) and (' *( ' .. main_jp.reading .. ' )*') or ''

  local is_common = item.is_common and ' `⭐ Common`' or ''
  local jlpt = (item.jlpt and #item.jlpt > 0) and (' `' .. string_upper(item.jlpt[1]) .. '`') or ''

  lines[#lines + 1] = string_format('## %s%s%s%s', word_jp, reading, is_common, jlpt)
  spacer(lines, layout)

  -- Other forms (additional japanese entries)
  if #jp_list > 1 then
    local other_forms = {}
    for i = 2, #jp_list do
      local jp = jp_list[i]
      local w = jp.word or ''
      local r = jp.reading or ''
      if w ~= '' and r ~= '' and w ~= r then
        other_forms[#other_forms + 1] = string_format('%s *( %s )*', w, r)
      elseif w ~= '' then
        other_forms[#other_forms + 1] = w
      elseif r ~= '' then
        other_forms[#other_forms + 1] = r
      end
    end
    if #other_forms > 0 then
      lines[#lines + 1] = '**Other forms:** ' .. table_concat(other_forms, ', ')
      spacer(lines, layout)
    end
  end

  -- Tags
  if item.tags and #item.tags > 0 then
    lines[#lines + 1] = '**Tags:** ' .. table_concat(item.tags, ', ')
    spacer(lines, layout)
  end

  -- Senses
  local senses = item.senses or {}
  for j = 1, #senses do
    local sense = senses[j]
    local eng = table_concat(sense.english_definitions or {}, ', ')
    local pos = ''
    if sense.parts_of_speech and #sense.parts_of_speech > 0 then
      pos = '`[' .. table_concat(sense.parts_of_speech, ', ') .. ']` '
    end
    lines[#lines + 1] = string_format('- **%d.** %s%s', j, pos, eng)

    -- Info/usage notes
    if sense.info and #sense.info > 0 then
      for _, note in ipairs(sense.info) do
        lines[#lines + 1] = '  > ' .. note
      end
    end

    -- See also
    if sense.see_also and #sense.see_also > 0 then
      lines[#lines + 1] = '  **See also:** ' .. table_concat(sense.see_also, ', ')
    end

    -- Sense tags
    if sense.tags and #sense.tags > 0 then
      lines[#lines + 1] = '  **Tags:** ' .. table_concat(sense.tags, ', ')
    end

    spacer(lines, layout)
  end

  return lines
end

local function process_response(word, config, callbacks, err, json_str)
  -- Clean up in-flight
  in_flight[word] = nil

  if err or not json_str then
    for _, cb in ipairs(callbacks) do
      vim_schedule(function() cb(nil, err or 'Empty response') end)
    end
    stop_spinner(false, word, err)
    return
  end

  local ok, parsed = pcall(vim_json_decode, json_str)
  if not ok or not parsed or not parsed.data or #parsed.data == 0 then
    for _, cb in ipairs(callbacks) do
      vim_schedule(function() cb(nil, 'Word not found') end)
    end
    stop_spinner(false, word, 'Word not found')
    return
  end

  local all_lines = {}
  local data = parsed.data
  local len = math_min(5, #data)

  for i = 1, len do
    local item = data[i]
    local item_lines = build_lines(item, config)
    for _, line in ipairs(item_lines) do
      all_lines[#all_lines + 1] = line
    end
    style.spacer(all_lines, config.layout)
    all_lines[#all_lines + 1] = '---'
    style.spacer(all_lines, config.layout)
  end

  local title = ' 辞書 Jisho.org: ' .. word .. ' '
  local timestamp = os_time()

  -- Cache the result
  search_cache[word] = {
    lines = all_lines,
    title = title,
    timestamp = timestamp,
    word = word
  }
  add_to_history(word, timestamp)
  save_cache()

  for _, cb in ipairs(callbacks) do
    vim_schedule(function() cb(all_lines, title, word) end)
  end

  stop_spinner(true, word)
end

function M.search(word, config)
  if not word or word == '' then
    word = vim_fn_expand('<cword>')
  end

  word = string_gsub(vim_trim(word), '%s+', ' ')

  if not word or word == '' then
    vim_notify('Please provide the Japanese word to query.', vim_log_levels.WARN)
    return
  end

  -- Check cache
  local cached = search_cache[word]
  local now = os_time()
  if cached and (now - cached.timestamp) < CACHE_TTL then
    vim_schedule(function()
      vim_notify('✓ Query successful (cached): ' .. word, vim_log_levels.INFO,
        { title = 'Jisho.org', id = 'jisho_req', timeout = 10 })
      require('jisho.ui').open_window(cached.lines, cached.title, config)
    end)
    add_to_history(word, now)
    return
  end

  -- Request deduplication
  local callbacks = { function(lines, title, _)
    if lines then
      require('jisho.ui').open_window(lines, title, config)
    else
      -- Error handled in process_response
    end
  end }

  if in_flight[word] then
    table.insert(in_flight[word].callbacks, callbacks[1])
    return
  end

  in_flight[word] = { callbacks = callbacks }

  -- Start spinner
  start_spinner(word)

  local url = 'https://jisho.org/api/v1/search/words'

  if vim_net_request then
    local query_url = url .. '?keyword=' .. urlencode(word)
    vim_net_request(query_url, {}, function(err, response)
      process_response(word, config, in_flight[word] and in_flight[word].callbacks or callbacks, err,
        response and response.body)
    end)
  else
    vim_system({ 'curl', '-s', '-G', '--data-urlencode', 'keyword=' .. word, url }, { text = true },
      function(obj)
        if obj.code ~= 0 or not obj.stdout then
          process_response(word, config, in_flight[word] and in_flight[word].callbacks or callbacks,
            'cURL Code: ' .. tostring(obj.code), nil)
        else
          process_response(word, config, in_flight[word] and in_flight[word].callbacks or callbacks,
            nil, obj.stdout)
        end
      end)
  end
end

function M.history(config)
  config = config or M.config
  if #search_history == 0 then
    vim_notify('No search history', vim_log_levels.INFO, { title = 'Jisho.org' })
    return
  end

  -- Try snacks picker first
  if config.use_snacks then
    local ok, snacks = pcall(require, 'snacks')
    if ok and snacks.picker then
      local items = {}
      for i, entry in ipairs(search_history) do
        local time_str = os.date('%Y-%m-%d %H:%M', entry.timestamp)
        items[#items + 1] = {
          text = string_format('%d. %s (%s)', i, entry.word, time_str),
          word = entry.word,
          idx = i,
        }
      end
      snacks.picker({
        title = ' 🏮 Jisho History ',
        items = items,
        layout = {
          preset = 'select',
          layout = {
            width = 0.45,
            height = 0.4,
            backdrop = 60
          }
        },
        format = function(item, _)
          local hl_text = 'Normal'
          local hl_icon = 'DiagnosticHint'
          local icon = '󰋚 '
          return {
            { ' ' .. icon .. ' ', hl_icon },
            { item.text, hl_text },
          }
        end,
        confirm = function(picker, item)
          picker:close()
          vim_schedule(function() M.search(item.word, config) end)
        end,
      })
      return
    end
  end

  -- Fallback: native window
  local lines = { '# Search History', '' }
  for i, entry in ipairs(search_history) do
    local time_str = os.date('%Y-%m-%d %H:%M', entry.timestamp)
    lines[#lines + 1] = string_format('%d. **%s** *(%s)*', i, entry.word, time_str)
  end

  local buf = vim_api.nvim_create_buf(false, true)
  vim_api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim_bo[buf].filetype = 'markdown'
  vim_bo[buf].modifiable = false
  vim_bo[buf].bufhidden = 'wipe'

  local win_width = math.floor(vim.o.columns * 0.5)
  local win_height = math.min(math.floor(vim.o.lines * 0.6), #lines + 4)
  local row = math.floor((vim.o.lines - win_height) / 2)
  local col = math.floor((vim.o.columns - win_width) / 2)

  local win = vim_api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    border = 'rounded',
    title = ' Jisho Search History ',
    title_pos = 'center',
    style = 'minimal',
    zindex = 50,
  })

  vim_wo[win].wrap = true
  vim_wo[win].conceallevel = 2
  vim_wo[win].cursorline = true
  vim_wo[win].number = false
  vim_wo[win].relativenumber = false
  vim_wo[win].signcolumn = 'no'

  local close_cmd = function()
    if vim_api.nvim_win_is_valid(win) then vim_api.nvim_win_close(win, true) end
  end
  vim.keymap.set('n', 'q', close_cmd, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set('n', '<Esc>', close_cmd, { buffer = buf, nowait = true, silent = true })

  vim.keymap.set('n', '<CR>', function()
    local cursor = vim_api.nvim_win_get_cursor(win)
    local line = vim_api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1]
    local word = line:match('%*%*(.-)%*%*')
    if word then
      close_cmd()
      vim_schedule(function() M.search(word, config) end)
    end
  end, { buffer = buf, nowait = true, silent = true })
end

function M.setup(opts)
  M.config = opts or {}
  load_cache()
end

return M
