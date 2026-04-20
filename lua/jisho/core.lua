local M = {}

local style = require('jisho.style')

local function urlencode(str)
  if not str then return '' end
  str = str:gsub('\n', '\r\n')
  str = str:gsub('([^%w %-%_%.%~])', function(c)
    return string.format('%%%02X', string.byte(c))
  end)
  str = str:gsub(' ', '+')
  return str
end

function M.search(word, config)
  if not word or word == '' then
    word = vim.fn.expand('<cword>')
  end

  word = vim.trim(word):gsub('%s+', ' ')

  if not word or word == '' then
    vim.notify('Please provide the Japanese word to query.', vim.log.levels.WARN)
    return
  end

  vim.notify('Searching: ' .. word, vim.log.levels.INFO, { title = 'Jisho.org', id = 'jisho_req' })

  local url = 'https://jisho.org/api/v1/search/words'

  local function process_response(err, json_str)
    if err or not json_str then
      vim.schedule(function()
        vim.notify('API request failed, please check internet connection\n' .. (err or ''),
          vim.log.levels.ERROR, { title = 'Jisho.org' })
      end)
      return
    end

    local ok, parsed = pcall(vim.json.decode, json_str)
    if not ok or not parsed or not parsed.data or #parsed.data == 0 then
      vim.schedule(function()
        vim.notify('Word not found: ' .. word, vim.log.levels.WARN, { title = 'Jisho.org' })
      end)
      return
    end

    local lines = {}
    for i = 1, math.min(5, #parsed.data) do
      local item = parsed.data[i]
      local jp = item.japanese[1]

      local word_jp = jp.word or jp.reading or 'Unknown'
      local reading = (jp.word and jp.reading) and (' *( ' .. jp.reading .. ' )*') or ''

      local is_common = item.is_common and ' `⭐ Common`' or ''
      local jlpt = (item.jlpt and #item.jlpt > 0) and (' `' .. string.upper(item.jlpt[1]) .. '`') or ''

      table.insert(lines, '## ' .. word_jp .. reading .. is_common .. jlpt)
      style.spacer(lines, config.layout)

      for j, sense in ipairs(item.senses) do
        local eng = table.concat(sense.english_definitions, ', ')
        local pos = ''
        if sense.parts_of_speech and #sense.parts_of_speech > 0 then
          pos = '`[' .. table.concat(sense.parts_of_speech, ', ') .. ']` '
        end
        table.insert(lines, '- **' .. j .. '.** ' .. pos .. eng)
      end
      style.spacer(lines, config.layout)
      table.insert(lines, '---')
      style.spacer(lines, config.layout)
    end

    vim.schedule(function()
      vim.notify('Query successful', vim.log.levels.INFO,
        { title = 'Jisho.org', id = 'jisho_req', timeout = 10 })

      local title = ' 辞書 Jisho.org: ' .. word .. ' '
      require('jisho.ui').open_window(lines, title, config)
    end)
  end

  if vim.net and vim.net.request then
    local query_url = url .. '?keyword=' .. urlencode(word)
    vim.net.request(query_url, {}, function(err, response)
      if err then process_response(err, nil) else process_response(nil, response and response.body) end
    end)
  else
    vim.system({ 'curl', '-s', '-G', '--data-urlencode', 'keyword=' .. word, url }, { text = true },
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
