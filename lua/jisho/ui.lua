local M = {}

function M.open_window(lines, title, config)
  -- use snacks.win
  if config.use_snacks then
    local ok, snacks = pcall(require, 'snacks')
    if ok then
      local win = snacks.win({
        text = lines,
        width = config.window.width,
        height = config.window.height,
        border = config.window.border,
        title = title,
        title_pos = 'center',
        bo = { filetype = 'markdown', buftype = 'nofile', swapfile = false },
        wo = { wrap = true, conceallevel = 2, number = true, cursorline = true },
        keys = { q = 'close', ['<Esc>'] = 'close' }
      })
      if win and win.buf and vim.api.nvim_buf_is_valid(win.buf) then
        vim.bo[win.buf].modifiable = false
      end
      return
    end
  end

  -- 方案 B: use native win
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local ui = vim.api.nvim_list_uis()[1]
  local win_width = math.floor(ui.width * config.window.width)
  local win_height = math.floor(ui.height * config.window.height)
  local row = math.floor((ui.height - win_height) / 2)
  local col = math.floor((ui.width - win_width) / 2)

  local win_opts = {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    border = config.window.border,
    title = title,
    title_pos = "center",
    style = "minimal",
    zindex = 50,
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)

  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'

  vim.wo[win].wrap = true
  vim.wo[win].conceallevel = 2
  vim.wo[win].cursorline = true

  -- bind "quit" keymaps
  local close_cmd = function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  vim.keymap.set('n', 'q', close_cmd, { buf = buf, nowait = true, silent = true })
  vim.keymap.set('n', '<Esc>', close_cmd, { buf = buf, nowait = true, silent = true })
end

return M
