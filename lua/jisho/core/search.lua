local M = {}

local cache = require('jisho.core.cache')
local response = require('jisho.core.response')

local vim_schedule = vim.schedule
local vim_json_decode = vim.json.decode
local vim_net_request = vim.net and vim.net.request
local vim_system = vim.system
local os_time = os.time

local function process_response(word, config, callbacks, err, json_str)
  -- Clean up in-flight
  cache.in_flight[word] = nil
  if err or not json_str then
    vim.iter(callbacks):each(function(cb)
      vim_schedule(function() cb(nil, err or 'Empty response') end)
    end)
    cache.stop_spinner(false, word, err)
    return
  end

  local ok, parsed = pcall(vim_json_decode, json_str)
  if not ok or not parsed or not parsed.data or #parsed.data == 0 then
    vim.iter(callbacks):each(function(cb)
      vim_schedule(function() cb(nil, 'Word not found') end)
    end)
    cache.stop_spinner(false, word, 'Word not found')
    return
  end

  local all_lines = {}
  local data = parsed.data
  local len = math.min(5, #data)

  for i = 1, len do
    local item = data[i]
    local item_lines = response.build_lines(item, config)
    vim.iter(item_lines):each(function(line)
      all_lines[#all_lines + 1] = line
    end)
    require('jisho.style').spacer(all_lines, config.layout)
    all_lines[#all_lines + 1] = '---'
    require('jisho.style').spacer(all_lines, config.layout)
  end
  local title = ' 辞書 Jisho.org: ' .. word .. ' '
  local timestamp = os_time()

  -- Cache the result
  cache.search_cache[word] = {
    lines = all_lines,
    title = title,
    timestamp = timestamp,
    word = word
  }
  cache.add_to_history(word, timestamp)
  cache.save_cache()
  vim.iter(callbacks):each(function(cb)
    vim_schedule(function() cb(all_lines, title, word) end)
  end)

  cache.stop_spinner(true, word)
end

function M.search(word, config)
  if not word or word == '' then
    word = vim.fn.expand('<cword>')
  end

  word = string.gsub(vim.trim(word), '%s+', ' ')

  if not word or word == '' then
    vim.notify('Please provide the Japanese word to query.', vim.log.levels.WARN)
    return
  end

  -- Check cache
  local cached = cache.search_cache[word]
  local now = os_time()
  if cached and (now - cached.timestamp) < cache.CACHE_TTL then
    vim_schedule(function()
      vim.notify('✓ Query successful (cached): ' .. word, vim.log.levels.INFO,
        { title = 'Jisho.org', id = 'jisho_req', timeout = 10 })
      require('jisho.ui').open_window(cached.lines, cached.title, config)
    end)
    cache.add_to_history(word, now)
    return
  end

  -- Request deduplication
  local callbacks = { function(lines, title, _)
    if lines then
      require('jisho.ui').open_window(lines, title, config)
    end
  end }

  if cache.in_flight[word] then
    table.insert(cache.in_flight[word].callbacks, callbacks[1])
    return
  end

  local url = 'https://jisho.org/api/v1/search/words'

  cache.start_spinner(word)

  if vim_net_request then
    local query_url = url .. '?keyword=' .. cache.urlencode(word)
    vim_net_request(query_url, {
      retry = 3,
      verbose = false,
    }, function(err, response)
      process_response(word, config,
        cache.in_flight[word] and cache.in_flight[word].callbacks or callbacks, err,
        response and response.body)
    end)
  else
    vim_system({ 'curl', '-s', '-G', '--data-urlencode', 'keyword=' .. word, url }, { text = true },
      function(obj)
        if obj.code ~= 0 or not obj.stdout then
          process_response(word, config,
            cache.in_flight[word] and cache.in_flight[word].callbacks or callbacks,
            'cURL Code: ' .. tostring(obj.code), nil)
        else
          process_response(word, config,
            cache.in_flight[word] and cache.in_flight[word].callbacks or callbacks, nil, obj.stdout)
        end
      end)
  end
end

return M

