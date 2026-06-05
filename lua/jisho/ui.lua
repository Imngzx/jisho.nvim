local M = {}

local pcall = pcall
local math_floor = math.floor
local string_find = string.find

local vim_api = vim.api
local nvim_win_get_cursor = vim_api.nvim_win_get_cursor
local nvim_buf_get_lines = vim_api.nvim_buf_get_lines
local nvim_win_set_cursor = vim_api.nvim_win_set_cursor
local nvim_create_buf = vim_api.nvim_create_buf
local nvim_buf_set_lines = vim_api.nvim_buf_set_lines
local nvim_open_win = vim_api.nvim_open_win
local nvim_buf_is_valid = vim_api.nvim_buf_is_valid
local nvim_win_is_valid = vim_api.nvim_win_is_valid
local nvim_win_close = vim_api.nvim_win_close
local nvim_exec_autocmds = vim_api.nvim_exec_autocmds

local vim_cmd = vim.cmd
local vim_keymap_set = vim.keymap.set
local vim_o = vim.o
local vim_bo = vim.bo
local vim_wo = vim.wo

local function setup_budoux_jumps(buf, config)
  if not config.use_budoux then return end
  local ok, budoux = pcall(require, 'budoux')
  if not ok then return end

  if not M._budoux_parser then
    M._budoux_parser = budoux.load_japanese_model()
  end

  local function jump(dir)
    local cursor = nvim_win_get_cursor(0)
    local row = cursor[1]
    local col = cursor[2] + 1
    local line = nvim_buf_get_lines(buf, row - 1, row, false)[1]

    if not line or not string_find(line, "[\128-\255]") then
      vim_cmd('normal! ' .. dir)
      return
    end

    local segments = M._budoux_parser.parse(line)
    local boundaries = { 1 }
    local current = 1

    for i = 1, #segments do
      current = current + #segments[i]
      boundaries[#boundaries + 1] = current
    end

    if dir == 'w' then
      for i = 1, #boundaries do
        local b = boundaries[i]
        if b > col then
          if b <= #line then
            nvim_win_set_cursor(0, { row, b - 1 })
            return
          end
        end
      end
      vim_cmd('normal! w')
    elseif dir == 'b' then
      for i = #boundaries, 1, -1 do
        local b = boundaries[i]
        if b < col then
          nvim_win_set_cursor(0, { row, b - 1 })
          return
        end
      end
      vim_cmd('normal! b')
    end
  end

  vim_keymap_set('n', 'w', function() jump('w') end, { buf = buf, silent = true, desc = "Budoux Word" })
  vim_keymap_set('n', 'b', function() jump('b') end, { buf = buf, silent = true, desc = "Budoux Back" })
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
      if win and win.buf and nvim_buf_is_valid(win.buf) then
        vim_bo[win.buf].modifiable = false
        setup_budoux_jumps(win.buf, config)

        nvim_exec_autocmds('User', {
          pattern = 'JishoWindowOpened',
          modeline = false,
          data = { buf = win.buf, win = win.win }
        })
      end
      return
    end
  end

  -- Plan B: uses native win
  local buf = nvim_create_buf(false, true)
  nvim_buf_set_lines(buf, 0, -1, false, lines)

  local win_width = math_floor(vim_o.columns * config.window.width)
  local win_height = math_floor(vim_o.lines * config.window.height)
  local row = math_floor((vim_o.lines - win_height) / 2)
  local col = math_floor((vim_o.columns - win_width) / 2)

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

  local win = nvim_open_win(buf, true, win_opts)

  vim_bo[buf].filetype = 'markdown'
  vim_bo[buf].modifiable = false
  vim_bo[buf].bufhidden = 'wipe'

  vim_wo[win].wrap = true
  vim_wo[win].conceallevel = 2
  vim_wo[win].cursorline = true
  vim_wo[win].number = false
  vim_wo[win].relativenumber = false
  vim_wo[win].signcolumn = "no"
  vim_wo[win].statuscolumn = ""
  vim_wo[win].foldcolumn = "0"
  vim_wo[win].spell = false
  vim_wo[win].list = false

  -- bind "quit" keymaps
  local close_cmd = function()
    if nvim_win_is_valid(win) then nvim_win_close(win, true) end
  end
  vim_keymap_set('n', 'q', close_cmd, { buf = buf, nowait = true, silent = true })
  vim_keymap_set('n', '<Esc>', close_cmd, { buf = buf, nowait = true, silent = true })

  setup_budoux_jumps(buf, config)

  nvim_exec_autocmds('User', {
    pattern = 'JishoWindowOpened',
    modeline = false,
    data = { buf = buf, win = win }
  })
end

return M
