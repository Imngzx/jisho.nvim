local M = {}

local pcall = pcall
local mfloor = math.floor
local sfind = string.find
local srequire = require

local vapi = vim.api
local nwin_gc = vapi.nvim_win_get_cursor
local nbuf_gl = vapi.nvim_buf_get_lines
local nwin_sc = vapi.nvim_win_set_cursor
local nbuf_cr = vapi.nvim_create_buf
local nbuf_sl = vapi.nvim_buf_set_lines
local nwin_op = vapi.nvim_open_win
local nbuf_iv = vapi.nvim_buf_is_valid
local nwin_iv = vapi.nvim_win_is_valid
local nwin_cl = vapi.nvim_win_close
local napi_ea = vapi.nvim_exec_autocmds
local nbuf_at = vapi.nvim_buf_attach

local vcmd = vim.cmd
local vkmap = vim.keymap.set
local vo = vim.o
local vbo = vim.bo
local vwo = vim.wo

local budoux_cache = {}

local function setup_budoux(buf, cfg)
  if not cfg.use_budoux then return end
  local ok, budoux = pcall(srequire, 'budoux')
  if not ok then return end
  if not M._budoux_parser then
    M._budoux_parser = budoux.load_japanese_model()
  end
  budoux_cache[buf] = {}
  nbuf_at(buf, false, { on_lines = function() budoux_cache[buf] = {} end })
  local function get_bnds(lnum, ltxt)
    local bc = budoux_cache[buf]
    local c = bc[lnum]
    if c and c.txt == ltxt then return c.bnds end
    local segs = M._budoux_parser.parse(ltxt)
    local bnds = { 1 }
    local cur = 1
    for i = 1, #segs do
      cur = cur + #segs[i]
      bnds[#bnds + 1] = cur
    end
    bc[lnum] = { bnds = bnds, txt = ltxt }
    return bnds
  end
  local function jump(dir)
    local cur = nwin_gc(0)
    local row, col = cur[1], cur[2] + 1
    local line = nbuf_gl(buf, row - 1, row, false)[1]
    if not line or not sfind(line, '[\128-\255]') then
      vcmd('normal! ' .. dir)
      return
    end
    local bnds = get_bnds(row, line)
    if dir == 'w' then
      for i = 1, #bnds do
        local b = bnds[i]
        if b > col and b <= #line then
          nwin_sc(0, { row, b - 1 })
          return
        end
      end
      vcmd('normal! w')
    else
      for i = #bnds, 1, -1 do
        local b = bnds[i]
        if b < col then
          nwin_sc(0, { row, b - 1 })
          return
        end
      end
      vcmd('normal! b')
    end
  end
  vkmap('n', 'w', function() jump('w') end, { buf = buf, silent = true, desc = 'Budoux Word' })
  vkmap('n', 'b', function() jump('b') end, { buf = buf, silent = true, desc = 'Budoux Back' })
end

local function setup_nav(buf, win, navl)
  local targs = {}
  for i = 1, #navl do
    local l = navl[i]
    if sfind(l, '^## ') or sfind(l, '^%- %*%*%d+%*%*') then
      targs[#targs + 1] = i
    end
  end
  local function nav(dir)
    if #targs == 0 then return end
    local cur = nwin_gc(win)
    local row = cur[1]
    local idx = 1
    for i = 1, #targs do
      if targs[i] >= row then idx = i; break end
      idx = i + 1
    end
    if dir == 'j' then idx = math.min(idx + 1, #targs)
    else idx = math.max(idx - 1, 1) end
    nwin_sc(win, { targs[idx], 0 })
  end
  vkmap('n', 'j', function() nav('j') end, { buf = buf, silent = true, desc = 'Next sense/entry' })
  vkmap('n', 'k', function() nav('k') end, { buf = buf, silent = true, desc = 'Prev sense/entry' })
end

function M.open_window(lines, title, cfg)
  local sn = cfg.use_snacks
  if sn then
    local ok, snacks = pcall(srequire, 'snacks')
    if ok then
      local win = snacks.win({
        text = lines, width = cfg.window.width, height = cfg.window.height,
        border = cfg.window.border, title = title, title_pos = 'center',
        bo = { filetype = 'markdown', buftype = 'nofile', swapfile = false },
        wo = { wrap = true, conceallevel = 2, cursorline = true, number = false,
               relativenumber = false, signcolumn = 'no', statuscolumn = '',
               foldcolumn = '0', spell = false, list = false },
        keys = { q = 'close', ['<Esc>'] = 'close' }
      })
      if win and win.buf and nbuf_iv(win.buf) then
        vbo[win.buf].modifiable = false
        setup_budoux(win.buf, cfg)
        setup_nav(win.buf, win.win, lines)
        napi_ea('User', { pattern = 'JishoWindowOpened', modeline = false, data = { buf = win.buf, win = win.win } })
      end
      return
    end
  end
  local buf = nbuf_cr(false, true)
  nbuf_sl(buf, 0, -1, false, lines)
  local ww = mfloor(vo.columns * cfg.window.width)
  local wh = mfloor(vo.lines * cfg.window.height)
  local r = mfloor((vo.lines - wh) / 2)
  local c = mfloor((vo.columns - ww) / 2)
  local win = nwin_op(buf, true, { relative = 'editor', width = ww, height = wh, row = r, col = c,
    border = cfg.window.border, title = title, title_pos = 'center', style = 'minimal', zindex = 50 })
  vbo[buf].filetype = 'markdown'
  vbo[buf].modifiable = false
  vbo[buf].bufhidden = 'wipe'
  vwo[win].wrap = true
  vwo[win].conceallevel = 2
  vwo[win].cursorline = true
  vwo[win].number = false
  vwo[win].relativenumber = false
  vwo[win].signcolumn = 'no'
  vwo[win].statuscolumn = ''
  vwo[win].foldcolumn = '0'
  vwo[win].spell = false
  vwo[win].list = false
  local close = function() if nwin_iv(win) then nwin_cl(win, true) end end
  vkmap('n', 'q', close, { buf = buf, nowait = true, silent = true })
  vkmap('n', '<Esc>', close, { buf = buf, nowait = true, silent = true })
  setup_budoux(buf, cfg)
  setup_nav(buf, win, lines)
  napi_ea('User', { pattern = 'JishoWindowOpened', modeline = false, data = { buf = buf, win = win } })
end

return M