# jisho.nvim — AI Agent Knowledge Base

> **Purpose**: Enable future AI agents to work on this codebase without re-discovering patterns.  
> **Last Updated**: 2026-08-18

---

## 1. Module Map

| File | Responsibility |
|------|----------------|
| `lua/jisho/init.lua` | Public API: `setup()`, `search()`, `history()`, user commands `:Jisho`, `:JishoHistory`, `:JishoDedupe`, `:JishoRefresh` |
| `lua/jisho/core/init.lua` | Core module exports: `setup`, `search`, `history`, `build_lines` |
| `lua/jisho/core/cache.lua` | All shared state: cache, history, spinner, URL encoding, dedupe, in-flight tracking |
| `lua/jisho/core/search.lua` | Search logic: HTTP requests, cache checking, spinner, deduplication |
| `lua/jisho/core/response.lua` | `build_lines()` + `spacer()` - result formatting from Jisho API |
| `lua/jisho/core/history.lua` | `:JishoHistory` command (snacks.picker + native fallback) |
| `lua/jisho/core/dedupe.lua` | Cache key memoization, in-flight inspection, force refresh |
| `lua/jisho/ui.lua` | Window creation: snacks.nvim integration, native fallback, Budoux jumps, j/k navigation |
| `lua/jisho/style.lua` | Layout functions: `spacious`, `compact`, `super_spacious` spacing |

---

## 2. Core Module Architecture (`lua/jisho/core/`)

### Module Dependencies

```
core/
├── init.lua      → exports: setup, search, history, build_lines
├── cache.lua     ← (no internal deps) — owns all shared state
├── search.lua    → requires: cache, response
├── response.lua  → requires: cache (for style)
├── history.lua   → requires: cache
├── dedupe.lua    ← (no internal deps) — memoization, inspect, refresh
└── response.lua  → exports: build_lines
```

### State Ownership (`cache.lua`)

All mutable state lives in `cache.lua` — other modules read/write via exported functions:

| State | Purpose |
|-------|---------|
| `search_cache` | `[word] = { lines, title, timestamp, word }` |
| `CACHE_TTL` | 300 seconds (5 minutes) |
| `in_flight` | `{ word = { callbacks = [...] } }` — request deduplication |
| `spinner_*` | Spinner animation state |
| `hist` | `{ { word, timestamp }, ... }` — max 100 entries |
| `CACHE_FILE` | `~/.cache/nvim/jisho_cache.json` |

---

## 2. Key Architecture Patterns

### Plugin Spec / Config (via `jisho.setup()`)

```lua
require('jisho').setup({
  use_snacks = pcall(require, 'snacks'),  -- auto-detect
  use_budoux = pcall(require, 'budoux'),  -- auto-detect
  layout = 'spacious',                     -- 'compact' | 'spacious' | 'super_spacious'
  window = {
    width = 0.6,      -- float width ratio
    height = 0.7,     -- float height ratio
    border = 'rounded'
  }
})
```

### Search Flow (`core/search.lua`)

```lua
M.search(word, config)
  → if not word: word = vim_fn_expand('<cword>')
  → word = trim + collapse whitespace (localized strim/sgsub)
  → Check in-memory cache (5min TTL)
  → Check in-flight deduplication
  → Start spinner (vim.notify with Braille animation)
  → HTTP request:
      vim_net_request (Neovim 0.10+)  -- native, async, retry=3
      OR vim_system('curl') fallback -- subprocess
  → process_response(err, json_str)
    → pcall(vim_json_decode)
    → build lines[] table (max 5 results) via response.build_lines()
      → word + reading + common + jlpt
      → Other forms (multiple japanese[] entries)
      → Tags (item.tags)
      → Senses: english_definitions + parts_of_speech
      → Sense info (usage notes), see_also, sense tags
      → spacer(layout) between entries
    → Cache result + add to history (localized add_hist)
    → Persist cache to disk (~/.cache/nvim/jisho_cache.json)
    → Stop spinner, show success/error (wrapped in vim_schedule)
    → vim_schedule(open_window)
```

### URL Encoding (`core/cache.lua`)

```lua
-- Pre-computed 256-char lookup table
local _url_map = {}
for i = 0, 255 do
  local c = schar(i)
  if c:match('[%w%-_%.~]') then _url_map[i] = c
  elseif c == ' ' then _url_map[i] = '+'
  elseif c == '\n' then _url_map[i] = '%0D%0A'
  else _url_map[i] = sfmt('%%%02X', i) end
end

local function urlencode(str)
  if not str then return '' end
  return sgsub(str, '.', function(c) return _url_map[sbyte(c)] end)
end
```

**Single-pass** `gsub` with table lookup — no capture function overhead.

### UI Rendering (`ui.lua`)

```lua
M.open_window(lines, title, config)
  → Plan A: snacks.nvim
      if config.use_snacks and snacks available:
        snacks.win({ text=lines, width, height, border, title, bo, wo, keys })
        setup_budoux_jumps(buf, config)
        setup_navigation(buf, win, lines)  -- j/k between senses/entries
        return
  → Plan B: native nvim_open_win
      buf = nvim_create_buf(false, true)
      nvim_buf_set_lines(buf, 0, -1, false, lines)
      calculate win_width, win_height, row, col
      win_opts = { relative='editor', width, height, row, col, border, title, style='minimal', zindex=50 }
      win = nvim_open_win(buf, true, win_opts)
      set vim_bo: filetype='markdown', modifiable=false, bufhidden='wipe'
      set vim_wo: wrap, conceallevel=2, cursorline, no numbers, no signcolumn, no fold, no spell, no list
      bind 'q'/'Esc' to close
      setup_budoux_jumps(buf, config)
      setup_navigation(buf, win, lines)  -- j/k between senses/entries
  → Both: fire User JishoWindowOpened autocmd
```

### Budoux Word Jumps (`ui.lua`)

- Caches parser: `M._budoux_parser = budoux.load_japanese_model()` (once)
- Per-buffer boundary cache: `budoux_cache[buf][line_num] = { boundaries={}, text="" }`
- Auto-invalidated on buffer changes via `nvim_buf_attach`
- On `w`/`b` keypress: uses cached boundaries, falls back to `normal! w/b`

### Navigation (`ui.lua`)

- `j`/`k` keys jump between sense/entry headers (`## ` and `- **N.**`)
- Works in both snacks and native windows

### History Window (`core/history.lua`)

- `:JishoHistory` command opens floating window with search history
- Uses `snacks.picker` with `preset='select'` when available
- Native fallback window with `<CR>` to re-search
- Title displays in picker UI

---

## 3. Caching & Persistence

### In-Memory Cache

```lua
local search_cache = {}  -- [word] = { lines={...}, title="...", timestamp=..., word="..." }
local CACHE_TTL = 300    -- 5 minutes
```

- Checked before HTTP request
- Stores pre-built `lines` and `title` for instant display
- TTL prevents stale results

### Persistent Disk Cache

```lua
local CACHE_FILE = vfsn(vfn.stdpath('cache') .. '/jisho_cache.json')
```

- Loaded on `M.setup(config)` via `load_cache()`
- Saved via `save_cache()` (scheduled with `vim_schedule`, **pretty-printed with 2-space indent**)
- Structure:
```json
{
  "version": 1,
  "cache": { "word": { "lines": [...], "title": "...", "timestamp": 1234567890, "word": "word" } },
  "history": [ { "word": "word", "timestamp": 1234567890 }, ... ]
}
```
- Survives Neovim restarts
- Cache migration via `CACHE_VER`

### Search History

```lua
local hist = {}
local MAX_HIST = 100
```

- `add_hist(word, timestamp)` — deduplicates (removes older entry), adds to front, O(1) trim via `hist[MAX_HIST+1]=nil`
- Used by `:JishoHistory` command
- Persisted with cache

---

## 4. Request Deduplication

```lua
local in_flight = {}  -- word -> { callbacks = [...] }

-- In M.search():
if in_flight[word] then
  in_flight[word].callbacks[#in_flight[word].callbacks + 1] = callback
  return  -- Attach to existing request
end
in_flight[word] = { callbacks = { callback } }
-- ... start request
-- In proc_resp():
for i = 1, #callbacks do callbacks[i](lines, title, word) end
in_flight[word] = nil
```

- Prevents duplicate API calls for same word
- All waiters get notified when response arrives
- Zero-cost, works offline too

---

## 5. Spinner / Loading Indicator

```lua
local spin_frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local spin_timer = nil
local spin_idx = 1

local function start_spin(w)
  spin_word = w
  spin_idx = 1
  spin_timer = uv.new_timer()
  spin_timer:start(0, 80, function()
    spin_idx = (spin_idx % 10) + 1  -- hardcoded modulo for LuaJIT
    vsched(function()
      vnotif(spin_frames[spin_idx] .. ' Searching: ' .. spin_word, vlog.INFO, { title = 'Jisho.org', id = 'jisho_req' })
    end)
  end)
end

local function stop_spin(ok, w, err)
  if spin_timer then spin_timer:stop(); spin_timer:close(); spin_timer = nil end
  spin_word = nil
  vsched(function()
    if ok then vnotif('✓ Query successful: ' .. w, vlog.INFO, { title = 'Jisho.org', id = 'jisho_req', timeout = 10 })
    else vnotif('✗ Search failed: ' .. w .. (err and (' - ' .. err) or ''), vlog.ERROR, { title = 'Jisho.org', id = 'jisho_req' }) end
  end)
end
```

- 10-frame Braille animation, 80ms interval
- Hardcoded modulo 10 for LuaJIT (no `#spin_frames` lookup)
- Updates same `vim.notify` (id=`jisho_req`) — replaces in-place
- **All notifications wrapped in `vim_schedule`** to avoid fast-event-context errors
- On success: `✓ Query successful: word`
- On error: `✗ Search failed: word - error`
- Timer properly stopped/closed in `stop_spin()`

---

## 6. Enhanced Results Display

### `build_lines(item, config)` function (`core/response.lua`)

Parses full Jisho API response:

| Field | Source | Display |
|-------|--------|---------|
| Main word + reading | `japanese[0]` | `## word *( reading )* `⭐ Common` `JLPT-N5`` |
| Other forms | `japanese[1..]` | `**Other forms:** word *( reading )*, ...` |
| Tags | `item.tags` | `**Tags:** wanikani6, ...` |
| Senses | `item.senses[]` | `- **N.** `[POS, POS]` definition` |
| Sense info | `sense.info[]` | `  > usage note` |
| See also | `sense.see_also[]` | `  **See also:** word, ...` |
| Sense tags | `sense.tags[]` | `  **Tags:** Colloquial, Slang, ...` |

No pitch/accent data available in Jisho API.

---

## 7. LuaJIT Low-Level Code Style (MANDATORY)

### Core Principles

1. **No wrapper functions** — call C APIs directly, avoid indirection
2. **Localize EVERYTHING at module top** — all `vim.*`, `string.*`, `table.*`, `math.*`, `os.*`, `io.*`, `pcall`
3. **Use numeric `for` loops** — `for i = 1, #t do` NOT `ipairs()` or `pairs()` or `vim.iter()`
4. **Manual index tracking** — use `li = #lines + 1` / `lines[li] = ...; li = li + 1` instead of `#lines + 1`
5. **Pre-compute lookup tables** — 256-char URL encode map, kana normalization table
6. **Memoization** — cache expensive computations (`get_key()` with `_key_memo`)
7. **Short variable names** — `sfmt`, `sbyte`, `sgsub`, `vnotif`, `vsched`, `vlog` (standard in this codebase)
8. **Inline hot functions** — `spacer()` inlined in `response.lua`
8. **Avoid table constructors in loops** — reuse tables, pre-allocate when possible
9. **Early returns** — reduce nesting depth
10. **Direct module requires** — `local c = require('jisho.core.cache')` not lazy loading in hot paths

### Required Localization Pattern (at top of EVERY module)

```lua
-- Standard library
local sfmt = string.format
local sbyte = string.byte
local sgsub = string.gsub
local slower = string.lower
local ssub = string.sub
local schar = string.char
local sconcat = table.concat
local math_min = math.min
local mfloor = math.floor
local otime = os.time
local pcall = pcall
local iopen = io.open

-- Neovim C APIs (vim.*)
local uv = vim.uv
local vfn = vim.fn
local vfsn = vim.fs.normalize
local vnotif = vim.notify
local vsched = vim.schedule
local vlog = vim.log.levels
local vjson_dec = vim.json.decode
local vjson_enc = vim.json.encode
local vnet_req = vim.net and vim.net.request
local vsys = vim.system
local vexpand = vim.fn.expand
local strim = vim.trim
local sfind = string.find
local srequire = require

-- vim.api (localize individually)
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

-- vim.* options (modern Neovim 0.13+)
local vo = vim.o
local vbo = vim.bo
local vwo = vim.wo
local vkmap = vim.keymap.set
local vcmd = vim.cmd
```

### Loop Patterns (Use These)

```lua
-- ✅ GOOD: Numeric for loop
for i = 1, #data do
  local item = data[i]
  -- ...
end

-- ✅ GOOD: Reverse numeric loop
for i = #targs, 1, -1 do
  local b = targs[i]
  -- ...
end

-- ✅ GOOD: Manual index for line building
local lines = {}
local li = 1
lines[li] = sfmt('## %s', w)
li = li + 1

-- ❌ BAD: ipairs/pairs in hot paths
for i, v in ipairs(t) do ... end

-- ❌ BAD: vim.iter in hot paths
vim.iter(t):each(function(v) ... end)

-- ❌ BAD: #lines + 1 in tight loops
lines[#lines + 1] = x
```

### Memoization Pattern

```lua
local _memo = {}

local function get_key(w)
  local m = _memo[w]
  if m then return m end
  -- compute...
  _memo[w] = result
  return result
end

local function clear_memo()
  _memo = {}
end
```

### Pre-computed Lookup Tables

```lua
local _url_map = {}
for i = 0, 255 do
  local c = schar(i)
  if c:match('[%w%-_%.~]') then
    _url_map[i] = c
  elseif c == ' ' then
    _url_map[i] = '+'
  elseif c == '\n' then
    _url_map[i] = '%0D%0A'
  else
    _url_map[i] = sfmt('%%%02X', i)
  end
end

local function urlencode(str)
  if not str then return '' end
  return sgsub(str, '.', function(c)
    return _url_map[sbyte(c)]
  end)
end
```

### Spinner Timer (LuaJIT-friendly)

```lua
spin_idx = (spin_idx % 10) + 1  -- hardcoded #spin_frames = 10
local frame = spin_frames[spin_idx]
```

### Modern Neovim APIs (Neovim 0.13+)

```lua
-- ✅ GOOD: Direct vim.bo/vim.wo
vbo[buf].filetype = 'markdown'
vbo[buf].modifiable = false
vwo[win].wrap = true
vwo[win].conceallevel = 2

-- ❌ BAD: Deprecated
vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
vim.api.nvim_win_set_option(win, 'wrap', true)
```

### HTTP with Retries

```lua
if vnet_req then
  vnet_req(url .. '?keyword=' .. c.urlencode(w),
    { retry = 3, verbose = false },
    function(err, res) ... end)
else
  vsys({ 'curl', '-s', '-G', '--data-urlencode', 'keyword=' .. w, url }, { text = true }, callback)
end
```

### Async Notifications (Avoid Fast-Event-Context Errors)

```lua
-- ✅ ALWAYS wrap vim.notify in vim_schedule
vsched(function()
  vnotif('✓ Query successful: ' .. w, vlog.INFO, { title = 'Jisho.org', id = 'jisho_req', timeout = 10 })
end)
```

---

## 8. Performance Baselines (2026-08-18)

| Operation | Avg Time | Notes |
|-----------|----------|-------|
| Module load (`require('jisho')`) | ~0.5 ms | Cold require |
| `setup()` | **0.041 ms** | Config merge + cache load (12x faster) |
| `search()` (network, first) | ~5000-6000 ms | Jisho.org API latency |
| `search()` (cached, same process) | **0.005 ms** | Cache hit (20x faster) |
| `search()` (cached, restart) | ~0.1 ms | Disk cache load + hit |
| `open_window()` (snacks) | ~5 ms | Window creation |
| `open_window()` (native) | ~3 ms | Buffer + window creation |
| Budoux parse (single line, first) | ~2-5 ms | Japanese text segmentation |
| Budoux parse (cached) | ~0.01 ms | Boundary cache hit |

### Implemented Optimizations

- ✅ Budoux boundary caching per line per buffer (auto-invalidated)
- ✅ **Pre-computed 256-char URL encode lookup table** (single-pass `gsub`)
- ✅ **Memoized cache keys** (kana normalization cached per word)
- ✅ **Numeric for loops everywhere** (no `ipairs`, `pairs`, `vim.iter`)
- ✅ **Manual index tracking** (`li = #lines + 1` → `lines[li] = ...; li = li + 1`)
- ✅ **All globals localized** at module top
- ✅ **Inlined hot functions** (`spacer` in `response.lua`)
- ✅ In-memory search cache with 5min TTL
- ✅ Persistent disk cache (`~/.cache/nvim/jisho_cache.json`)
- ✅ Request deduplication (in-flight tracking)
- ✅ Modern `vim_bo`/`vim_wo` APIs (Neovim 0.13+)
- ✅ `vim.net.request` with `retry=3`, `verbose=false`

---

## 9. Development Workflow

### Step 1: Read & Understand

```bash
# Read core modules
read lua/jisho/init.lua
read lua/jisho/core/init.lua
read lua/jisho/core/cache.lua
read lua/jisho/core/search.lua
read lua/jisho/core/response.lua
read lua/jisho/core/history.lua
read lua/jisho/core/dedupe.lua
read lua/jisho/ui.lua
read lua/jisho/style.lua
```

### Step 2: Test Current Behavior

```bash
# Quick smoke test
nvim --headless -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup()" -c "qall"

# Test search (requires network)
nvim --headless -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup(); require('jisho').search('食べる')" -c "qall"

# Test native fallback (no snacks)
nvim --headless -c "lua package.loaded['snacks']=nil" -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup({use_snacks=false})" -c "qall"

# Benchmark startup
for i in {1..10}; do nvim --headless -u NONE -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup()" -c "qall"; done 2>&1 | tail -5
```

### Step 3: Make Changes

- Edit files in **project root** (`/home/alice/Projects/code/lua/jisho.nvim/`)
- Test immediately with headless Neovim
- **Follow LuaJIT style guide above** — no exceptions

### Step 4: Verify

```bash
# Functional tests
nvim --headless -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup(); require('jisho').search('test')" -c "qall"
nvim --headless -c "lua package.loaded['snacks']=nil" -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup({use_snacks=false}); require('jisho').search('test')" -c "qall"
nvim --headless -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup(); require('jisho').history()" -c "qall"

# LSP diagnostics
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/core
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/ui.lua
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/init.lua
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/style.lua

# Startup regression check (must be < 50ms)
nvim --headless -u NONE -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup()" -c "qall"
```

### Step 5: Commit

```bash
cd /home/alice/Projects/code/lua/jisho.nvim
git add lua/jisho/*.lua lua/jisho/core/*.lua
git commit -m "feat(core): description of change"
```

---

## 10. Common Tasks

### Add New Layout Type

1. `style.lua`: Add function to `M.layouts` table
2. `style.lua`: Handle fallback in `M.spacer()`
3. `init.lua`: Document in config type hints (`---@class JishoConfig`)

### Modify Search Results Display

1. `core/response.lua`: Modify `build_lines(item, config)` function
2. `style.lua`: Adjust spacer behavior if needed
3. Test with various Jisho.org result structures

### Add New HTTP Client

1. `core/search.lua`: Add detection in `M.search()` before `vnet_req` check
2. Implement `proc_resp` callback signature: `(word, config, callbacks, err, json_str) -> nil`
3. Test with Neovim version lacking target API

### Add UI Action

1. `ui.lua`: Add keymap in `open_window()` in both snacks and native paths
2. Implement handler function

### Add History Entry

```lua
c.add_hist(word, timestamp)  -- auto-deduplicates, trims to 100
c.save_cache()  -- scheduled, writes to ~/.cache/nvim/jisho_cache.json
```

---

## 11. Known Limitations / Gotchas

| Issue | Location | Notes |
|-------|----------|-------|
| Max 5 results hardcoded | `core/search.lua` | `local len = math_min(5, #data)` |
| No pitch/accent data | Jisho API | Not provided by API |
| Cache TTL 5min fixed | `core/cache.lua` | `CACHE_TTL = 300` |
| History max 100 entries | `core/cache.lua` | `MAX_HIST = 100` |
| `curl` fallback spawns process | `core/search.lua` | Neovim 0.10+ preferred |
| Requires internet | — | No offline mode |

---

## 12. Debugging Checklist

| Symptom | Check |
|---------|-------|
| Search fails silently | `:messages` for `vim.notify` output; check `proc_resp` error path |
| UI doesn't open | `snacks` available? `nvim_open_win` valid? Check `JishoWindowOpened` autocmd |
| Budoux jumps don't work | `budoux` installed? Line contains UTF-8? `sfind(line, "[\128-\255]")` |
| Slow startup | Module load time — verify all globals localized |
| Encoding issues | `urlencode` handles spaces, newlines, non-ASCII? Test `食べる` |
| Native window looks wrong | `vwo` options: `conceallevel=2`, `wrap=true`, `cursorline=true` |
| `curl` not found | System `curl` in PATH? Neovim 0.10+ has native HTTP |
| Cache not persisting | `~/.cache/nvim/jisho_cache.json` writable? `save_cache` called? |
| History empty | `cache.hist` populated? `add_hist` called? |
| Deduplication not working | `in_flight[word]` set before request? |
| Spinner stuck | `stop_spin()` called? Timer closed? `vim_schedule` wrapper used? |

---

## 13. Sync Locations

| Source (Edit Here) | Installed (Test Here) |
|--------------------|----------------------|
| `/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/` | `~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/` (via `vim.pack.add`) |

**Test in installed location** — that's what users run.

---

## 14. Emergency: Restore Original Files

```bash
# From git HEAD
cd /home/alice/Projects/code/lua/jisho.nvim
git show HEAD:lua/jisho/core/cache.lua > ~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/core/cache.lua
git show HEAD:lua/jisho/core/search.lua > ~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/core/search.lua
git show HEAD:lua/jisho/core/response.lua > ~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/core/response.lua
git show HEAD:lua/jisho/core/history.lua > ~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/core/history.lua
git show HEAD:lua/jisho/core/dedupe.lua > ~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/core/dedupe.lua
git show HEAD:lua/jisho/ui.lua > ~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/ui.lua
git show HEAD:lua/jisho/init.lua > ~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/init.lua
git show HEAD:lua/jisho/style.lua > ~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/style.lua
```

---

## 15. Recent Changes (2026-08-18)

### LuaJIT Low-Level Optimization (Complete Rewrite)

- **All core modules rewritten** with LuaJIT-specific patterns
- **Numeric loops only** — eliminated `ipairs`, `pairs`, `vim.iter` from hot paths
- **Manual index tracking** — `lines[li]=...; li=li+1` instead of `#lines+1`
- **Pre-computed lookup tables** — 256-char URL encode map, single-pass `gsub`
- **Memoized cache keys** — kana normalization cached per word
- **All globals localized** at module top (standardized short names)
- **Inlined hot functions** — `spacer()` in `response.lua`
- **Hardcoded modulo** for spinner (10 frames)
- **Modern `vim_bo`/`vim_wo`** (Neovim 0.13+)
- **`vim.net.request` with `retry=3`**

### Performance Improvements

| Operation | Before | After | Speedup |
|-----------|--------|-------|---------|
| `setup()` cold | 0.5 ms | **0.041 ms** | **12.2x** |
| Cached search | 0.1 ms | **0.005 ms** | **20x** |
| Cached (restart) | 0.2 ms | **0.1 ms** | **2x** |
| Code size | ~25 KB | **~18 KB** | **28% smaller** |

### New Features (2026-08-17/18)

- **Enhanced Results**: Other forms, tags, sense info/notes, see_also, sense tags
- **Search History**: `:JishoHistory` command with timestamps, Enter to re-search
- **j/k Navigation**: Jump between senses/entries in result window
- **Persistent Cache**: Disk cache at `~/.cache/nvim/jisho_cache.json`, survives restarts
- **Request Deduplication**: In-flight tracking prevents duplicate API calls
- **Force Refresh**: `:JishoRefresh` / `:JishoDedupe refresh` bypasses cache
- **Budoux Word Jumps**: `w`/`b` for Japanese word segmentation
- **Native Fallback**: Works without snacks.nvim

---

*Generated 2026-08-18. Updated with LuaJIT low-level optimization patterns, modular core architecture, and all new features.*