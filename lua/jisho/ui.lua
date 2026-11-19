local M = {}

local pcall = pcall
local mfloor = math.floor
local sfind = string.find
local sbyte = string.byte
local schar = string.char
local ssub = string.sub
local sfmt = string.format
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
local nbuf_lc = vapi.nvim_buf_line_count

local vcmd = vim.cmd
local vvar = vim.v
local vcharclass = vim.fn.charclass
local vstr_utf_start = vim.str_utf_start
local vkmap = vim.keymap.set
local vo = vim.o
local vbo = vim.bo
local vwo = vim.wo

-- Budoux word motions -------------------------------------------------------
--
-- Per line, `line_words()` lists where each word starts and ends (0-based byte
-- columns). Words follow Vim's own classes (`charclass()`), so English and
-- markup behave exactly like the built-in `w`/`b`/`e`/`ge`; only inside a run
-- of Japanese text the class changes (kanji <-> kana) are replaced by Budoux
-- phrase boundaries.

local budoux_cache = {}

-- charclass() for ASCII under the default 'iskeyword': 0 blank, 1 punct, 2 word.
local _acls = {}
for i = 0, 127 do
  if i == 32 or i == 9 then
    _acls[i] = 0
  elseif sfind(schar(i), '[%w_]') then
    _acls[i] = 2
  else
    _acls[i] = 1
  end
end

-- charclass() values that take part in a Japanese run: hiragana, katakana,
-- CJK ideographs. Non-ASCII punctuation (、。「」・…々, class 1) joins a run too.
local JP = { [0x3040] = true, [0x30a0] = true, [0x4e00] = true }

local function line_words(line, bset)
  local ws, we = {}, {}
  local n = 0
  local prev, prev_jp = 0, false
  local last = -1
  local i = 1
  local len = #line
  while i <= len do
    local b = sbyte(line, i)
    local cls, w, jp
    if b < 128 then
      cls, w, jp = _acls[b], 1, false
    else
      w = b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1
      cls = vcharclass(ssub(line, i, i + w - 1))
      jp = JP[cls] or cls == 1
    end
    if cls == 0 then
      if n > 0 and we[n] == nil then we[n] = last end
    else
      local start
      if jp and prev_jp then
        start = bset ~= nil and bset[i] == true
      else
        start = cls ~= prev
      end
      if start then
        if n > 0 and we[n] == nil then we[n] = last end
        n = n + 1
        ws[n] = i - 1
      end
      last = i - 1
    end
    prev, prev_jp = cls, jp
    i = i + w
  end
  if n > 0 and we[n] == nil then we[n] = last end
  return ws, we, n
end

local function get_words(buf, lnum)
  local ltxt = nbuf_gl(buf, lnum - 1, lnum, false)[1] or ''
  local bc = budoux_cache[buf]
  local c = bc and bc[lnum]
  if c and c.txt == ltxt then return c.ws, c.we, c.n, ltxt end
  local bset
  if sfind(ltxt, '[\128-\255]') then
    bset = {}
    local segs = M._budoux_parser.parse(ltxt)
    local cur = 1
    for i = 1, #segs do
      bset[cur] = true
      cur = cur + #segs[i]
    end
  end
  local ws, we, n = line_words(ltxt, bset)
  if bc then bc[lnum] = { txt = ltxt, ws = ws, we = we, n = n } end
  return ws, we, n, ltxt
end

-- One step of `kind` ('w' | 'b' | 'e' | 'ge') from the cursor. Line crossing
-- matches Vim: an empty line is a stop for w/b/ge (not e), a blank-only line
-- never is. Returns false at the buffer edge.
local function step(buf, kind)
  local cur = nwin_gc(0)
  local row, col = cur[1], cur[2]
  local fwd = kind == 'w' or kind == 'e'
  local ws, we, n = get_words(buf, row)
  local pos = (kind == 'w' or kind == 'b') and ws or we
  if fwd then
    for i = 1, n do
      if pos[i] > col then
        nwin_sc(0, { row, pos[i] })
        return true
      end
    end
  else
    for i = n, 1, -1 do
      if pos[i] < col then
        nwin_sc(0, { row, pos[i] })
        return true
      end
    end
  end
  local last = nbuf_lc(buf)
  local r = fwd and row + 1 or row - 1
  while r >= 1 and r <= last do
    local rws, rwe, rn, l = get_words(buf, r)
    if l == '' then
      if kind ~= 'e' then
        nwin_sc(0, { r, 0 })
        return true
      end
    elseif rn > 0 then
      local p = (kind == 'w' or kind == 'b') and rws or rwe
      nwin_sc(0, { r, fwd and p[1] or p[rn] })
      return true
    end
    r = fwd and r + 1 or r - 1
  end
  -- At the buffer edge Vim still moves: `ge` to the first char, `w` to the last.
  if kind == 'ge' then
    if row ~= 1 or col ~= 0 then
      nwin_sc(0, { 1, 0 })
      return true
    end
  elseif kind == 'w' then
    local l = nbuf_gl(buf, row - 1, row, false)[1] or ''
    local lc = #l - 1
    if lc > col then
      lc = lc + vstr_utf_start(l, #l)
      if lc > col then
        nwin_sc(0, { row, lc })
        return true
      end
    end
  end
  return false
end

function M._budoux_jump(buf, kind)
  for _ = 1, vvar.count1 do
    if not step(buf, kind) then return end
  end
end

local function setup_budoux(buf, cfg)
  if not cfg.use_budoux then return end
  local ok, budoux = pcall(srequire, 'budoux')
  if not ok then return end
  if not M._budoux_parser then
    M._budoux_parser = budoux.load_japanese_model()
  end
  budoux_cache[buf] = {}
  nbuf_at(buf, false, {
    on_lines = function() budoux_cache[buf] = {} end,
    on_detach = function() budoux_cache[buf] = nil end,
  })
  local nx = { 'n', 'x' }
  local keys = { 'w', 'b', 'e', 'ge' }
  for i = 1, 4 do
    local k = keys[i]
    local opts = { buf = buf, silent = true, desc = 'Budoux ' .. k }
    vkmap(nx, k, function() M._budoux_jump(buf, k) end, opts)
    -- Operator-pending: w/b are exclusive like Vim's; `v` makes e/ge inclusive.
    vkmap('o', k, sfmt('%s<Cmd>lua require("jisho.ui")._budoux_jump(%d, %q)<CR>',
      (k == 'e' or k == 'ge') and 'v' or '', buf, k), opts)
  end
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
      if targs[i] >= row then
        idx = i; break
      end
      idx = i + 1
    end
    if dir == 'j' then
      idx = math.min(idx + 1, #targs)
    else
      idx = math.max(idx - 1, 1)
    end
    nwin_sc(win, { targs[idx], 0 })
    vcmd('normal! zt')
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
        text = lines,
        width = cfg.window.width,
        height = cfg.window.height,
        border = cfg.window.border,
        title = title,
        title_pos = 'center',
        bo = { filetype = 'markdown', buftype = 'nofile', swapfile = false },
        wo = {
          wrap = true,
          conceallevel = 2,
          cursorline = true,
          number = false,
          relativenumber = false,
          signcolumn = 'no',
          statuscolumn = '',
          foldcolumn = '0',
          spell = false,
          list = false
        },
        keys = { q = 'close', ['<Esc>'] = 'close' }
      })
      if win and win.buf and nbuf_iv(win.buf) then
        vbo[win.buf].modifiable = false
        setup_budoux(win.buf, cfg)
        setup_nav(win.buf, win.win, lines)
        napi_ea('User',
          { pattern = 'JishoWindowOpened', modeline = false, data = { buf = win.buf, win = win.win } })
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
  local win = nwin_op(buf, true, {
    relative = 'editor',
    width = ww,
    height = wh,
    row = r,
    col = c,
    border = cfg.window.border,
    title = title,
    title_pos = 'center',
    style = 'minimal',
    zindex = 50
  })
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
  napi_ea('User',
    { pattern = 'JishoWindowOpened', modeline = false, data = { buf = buf, win = win } })
end

return M
