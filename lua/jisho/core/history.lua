local M = {}

local cache = require('jisho.core.cache')

local string_format = string.format
local os_date = os.date
local vim_schedule = vim.schedule

function M.history(config)
  config = config or cache.config
  if #cache.search_history == 0 then
    vim.notify('No search history', vim.log.levels.INFO, { title = 'Jisho.org' })
    return
  end

  -- Try snacks picker first
  if config.use_snacks then
    local ok, snacks = pcall(require, 'snacks')
    if ok and snacks.picker then
      local items = {}
      for i, entry in ipairs(cache.search_history) do
        local time_str = os_date('%Y-%m-%d %H:%M', entry.timestamp)
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
            -- border = 'rounded',
            -- box = 'vertical',
            -- { win = 'input', height = 1, border = 'bottom' },
            -- { win = 'list', border = 'none' },
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
  for i, entry in ipairs(cache.search_history) do
    local time_str = os_date('%Y-%m-%d %H:%M', entry.timestamp)
    lines[#lines + 1] = string_format('%d. **%s** *(%s)*', i, entry.word, time_str)
  end

  local vim_api = vim.api
  local vim_bo = vim.bo
  local vim_wo = vim.wo

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

return M

