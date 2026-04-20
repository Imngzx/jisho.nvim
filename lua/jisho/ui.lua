local M = {}

local function setup_budoux_jumps(buf, config)
  if not config.use_budoux then return end
  local ok, budoux = pcall(require, 'budoux')
  if not ok then return end

  if not M._budoux_parser then
    M._budoux_parser = budoux.load_japanese_model()
  end

  local function jump(dir)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1]
    local col = cursor[2] + 1
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]

    if not line or not string.find(line, "[\128-\255]") then
      vim.cmd('normal! ' .. dir)
      return
    end

    local segments = M._budoux_parser.parse(line)
    local boundaries = { 1 }
    local current = 1
    for _, seg in ipairs(segments) do
      current = current + #seg
      table.insert(boundaries, current)
    end

    if dir == 'w' then
      for _, b in ipairs(boundaries) do
        if b > col then
          if b <= #line then
            vim.api.nvim_win_set_cursor(0, { row, b - 1 })
            return
          end
        end
      end
      vim.cmd('normal! w')
    elseif dir == 'b' then
      for i = #boundaries, 1, -1 do
        local b = boundaries[i]
        if b < col then
          vim.api.nvim_win_set_cursor(0, { row, b - 1 })
          return
        end
      end
      vim.cmd('normal! b')
    end
  end

  vim.keymap.set('n', 'w', function() jump('w') end, { buf = buf, silent = true, desc = "Budoux Word" })
  vim.keymap.set('n', 'b', function() jump('b') end, { buf = buf, silent = true, desc = "Budoux Back" })
end

function M.open_window(lines, title, config)
  -- Plan A: uses snacks win
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
        wo = {
          wrap = true,
          conceallevel = 2,
          cursorline = true,
          number = false,
          relativenumber = false,
          signcolumn = "no",
          statuscolumn = "",
          foldcolumn = "0",
          spell = false,
          list = false,
        },
        keys = { q = 'close', ['<Esc>'] = 'close' }
      })
      if win and win.buf and vim.api.nvim_buf_is_valid(win.buf) then
        vim.bo[win.buf].modifiable = false
        setup_budoux_jumps(win.buf, config)

        vim.api.nvim_exec_autocmds('User', {
          pattern = 'JishoWindowOpened',
          modeline = false,
          data = { buf = win.buf, win = win.win }
        })
      end
      return
    end
  end

  -- Plan B: uses native win
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local win_width = math.floor(vim.o.columns * config.window.width)
  local win_height = math.floor(vim.o.lines * config.window.height)
  local row = math.floor((vim.o.lines - win_height) / 2)
  local col = math.floor((vim.o.columns - win_width) / 2)

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
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].statuscolumn = ""
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].spell = false
  vim.wo[win].list = false

  -- bind "quit" keymaps
  local close_cmd = function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  vim.keymap.set('n', 'q', close_cmd, { buf = buf, nowait = true, silent = true })
  vim.keymap.set('n', '<Esc>', close_cmd, { buf = buf, nowait = true, silent = true })

  setup_budoux_jumps(buf, config)

  vim.api.nvim_exec_autocmds('User', {
    pattern = 'JishoWindowOpened',
    modeline = false,
    data = { buf = buf, win = win }
  })
end

return M
