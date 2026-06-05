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

local vim_notify = vim.notify
local vim_schedule = vim.schedule
local vim_fn_expand = vim.fn.expand
local vim_trim = vim.trim
local vim_log_levels = vim.log.levels
local vim_json_decode = vim.json.decode
local vim_net_request = vim.net and vim.net.request
local vim_system = vim.system

local function hex_format(c)
  return string_format('%%%02X', string_byte(c))
end

local function urlencode(str)
  if not str then return '' end
  str = string_gsub(str, '\n', '\r\n')
  str = string_gsub(str, '([^%w %-%_%.%~])', hex_format)
  str = string_gsub(str, ' ', '+')
  return str
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

  vim_notify('Searching: ' .. word, vim_log_levels.INFO, { title = 'Jisho.org', id = 'jisho_req' })

  local url = 'https://jisho.org/api/v1/search/words'

  local function process_response(err, json_str)
    if err or not json_str then
      vim_schedule(function()
        vim_notify('API request failed, please check internet connection\n' .. (err or ''),
          vim_log_levels.ERROR, { title = 'Jisho.org' })
      end)
      return
    end

    local ok, parsed = pcall(vim_json_decode, json_str)
    if not ok or not parsed or not parsed.data or #parsed.data == 0 then
      vim_schedule(function()
        vim_notify('Word not found: ' .. word, vim_log_levels.WARN, { title = 'Jisho.org' })
      end)
      return
    end

    local lines = {}
    local data = parsed.data
    local len = math_min(5, #data)

    for i = 1, len do
      local item = data[i]
      local jp = item.japanese[1]

      local word_jp = jp.word or jp.reading or 'Unknown'
      local reading = (jp.word and jp.reading) and (' *( ' .. jp.reading .. ' )*') or ''

      local is_common = item.is_common and ' `⭐ Common`' or ''
      local jlpt = (item.jlpt and #item.jlpt > 0) and (' `' .. string_upper(item.jlpt[1]) .. '`') or ''

      lines[#lines + 1] = '## ' .. word_jp .. reading .. is_common .. jlpt
      style.spacer(lines, config.layout)

      local senses = item.senses
      for j = 1, #senses do
        local sense = senses[j]
        local eng = table_concat(sense.english_definitions, ', ')
        local pos = ''
        if sense.parts_of_speech and #sense.parts_of_speech > 0 then
          pos = '`[' .. table_concat(sense.parts_of_speech, ', ') .. ']` '
        end
        lines[#lines + 1] = '- **' .. j .. '.** ' .. pos .. eng
      end

      style.spacer(lines, config.layout)
      lines[#lines + 1] = '---'
      style.spacer(lines, config.layout)
    end

    vim_schedule(function()
      vim_notify('Query successful', vim_log_levels.INFO,
        { title = 'Jisho.org', id = 'jisho_req', timeout = 10 })

      local title = ' 辞書 Jisho.org: ' .. word .. ' '
      require('jisho.ui').open_window(lines, title, config)
    end)
  end

  if vim_net_request then
    local query_url = url .. '?keyword=' .. urlencode(word)
    vim_net_request(query_url, {}, function(err, response)
      if err then process_response(err, nil) else process_response(nil, response and response.body) end
    end)
  else
    vim_system({ 'curl', '-s', '-G', '--data-urlencode', 'keyword=' .. word, url }, { text = true },
      function(obj)
        if obj.code ~= 0 or not obj.stdout then
          process_response('cURL Code: ' .. tostring(obj.code), nil)
        else
          process_response(nil, obj.stdout)
        end
      end)
  end
end

return M
