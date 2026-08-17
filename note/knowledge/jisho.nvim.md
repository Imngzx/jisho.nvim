# jisho.nvim — AI Agent Knowledge Base

> **Purpose**: Enable future AI agents to work on this codebase without re-discovering patterns.  
> **Last Updated**: 2026-08-17

---

## 1. Module Map

| File | Responsibility |
|------|----------------|
| `lua/jisho/init.lua` | Public API: `setup()`, `search()`, `history()`, user commands `:Jisho`, `:JishoHistory` |
| `lua/jisho/core.lua` | Search logic: URL encoding, HTTP request, response parsing, line generation, caching, history, deduplication |
| `lua/jisho/ui.lua` | Window creation: snacks.nvim integration, native fallback, Budoux jumps, j/k navigation |
| `lua/jisho/style.lua` | Layout functions: `spacious`, `compact`, `super_spacious` spacing |

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

### Search Flow (`core.lua`)

```lua
M.search(word, config)
  → if not word: word = vim_fn_expand('<cword>')
  → word = trim + collapse whitespace
  → Check in-memory cache (5min TTL)
  → Check in-flight deduplication
  → Start spinner (vim.notify with Braille animation)
  → HTTP request:
      vim_net_request (Neovim 0.10+)  -- native, async
      OR vim_system('curl') fallback -- subprocess
  → process_response(err, json_str)
    → pcall(vim_json_decode)
    → build lines[] table (max 5 results)
      → word + reading + common + jlpt
      → Other forms (multiple japanese[] entries)
      → Tags (item.tags)
      → Senses: english_definitions + parts_of_speech
      → Sense info (usage notes), see_also, sense tags
      → style.spacer(layout) between entries
    → Cache result + add to history
    → Persist cache to disk (~/.cache/nvim/jisho_cache.json)
    → Stop spinner, show success/error
    → vim_schedule(open_window)
```

### URL Encoding (`core.lua`)

```lua
local function urlencode(str)
  if not str then return '' end
  return string_gsub(str, '([^\r\n%w %-%_%.%~])', function(c)
    if c == ' ' then return '+' end
    if c == '\n' then return '%0D%0A' end
    return string_format('%%%02X', string_byte(c))
  end)
end
```

**Single-pass** with capture function — no longer 3 separate `gsub` passes.

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

### Budoux Word Jumps (`ui.lua:29-103`)

- Caches parser: `M._budoux_parser = budoux.load_japanese_model()` (once)
- Per-buffer boundary cache: `budoux_cache[buf][line_num] = { boundaries={}, text="" }`
- Auto-invalidated on buffer changes via `nvim_buf_attach`
- On `w`/`b` keypress: uses cached boundaries, falls back to `normal! w/b`

### Navigation (`ui.lua:105-138`)

- `j`/`k` keys jump between sense/entry headers (`## ` and `- **N.**`)
- Works in both snacks and native windows

### History Window (`core.lua:M.history()`)

- `:JishoHistory` command opens floating window with search history
- Shows numbered list with timestamps
- Press `<CR>` on entry to re-search that word

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
local CACHE_FILE = vim_fs_normalize(vim.fn.stdpath('cache') .. '/jisho_cache.json')
```

- Loaded on `M.setup(config)` via `load_cache()`
- Saved via `save_cache()` (scheduled with `vim_schedule`)
- Structure:
```json
{
  "version": 1,
  "cache": { "word": { "lines": [...], "title": "...", "timestamp": 1234567890, "word": "word" } },
  "history": [ { "word": "word", "timestamp": 1234567890 }, ... ]
}
```
- Survives Neovim restarts
- Cache migration via `CACHE_VERSION`

### Search History

```lua
local search_history = {}
local MAX_HISTORY = 100
```

- `add_to_history(word, timestamp)` — deduplicates (removes older entry), adds to front, trims to 100
- Used by `:JishoHistory` command
- Persisted with cache

---

## 4. Request Deduplication

```lua
local in_flight = {}  -- word -> { callbacks = [...] }

-- In M.search():
if in_flight[word] then
  table.insert(in_flight[word].callbacks, callback)
  return  -- Attach to existing request
end
in_flight[word] = { callbacks = { callback } }
-- ... start request
-- In process_response():
for _, cb in ipairs(callbacks) do cb(lines, title, word) end
in_flight[word] = nil
```

- Prevents duplicate API calls for same word
- All waiters get notified when response arrives
- Zero-cost, works offline too

---

## 5. Spinner / Loading Indicator

```lua
local spinner_frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local spinner_timer = uv.new_timer()
spinner_timer:start(0, 80, function()
  vim_schedule(function()
    vim_notify(frame .. ' Searching: ' .. word, INFO, { id = 'jisho_req' })
  end)
end)
```

- 10-frame Braille animation, 80ms interval
- Updates same `vim.notify` (id=`jisho_req`) — replaces in-place
- On success: `✓ Query successful: word`
- On error: `✗ Search failed: word - error`
- Timer properly stopped/closed in `stop_spinner()`

---

## 6. Enhanced Results Display

### `build_lines(item, config)` function

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

## 7. Performance Baselines (2026-08-17)

| Operation | Avg Time | Notes |
|-----------|----------|-------|
| `require('jisho')` | ~0.5 ms | Cold require |
| `setup()` | ~0.5 ms | Config merge + cache load |
| `search()` (network, first) | ~3000-4000 ms | Jisho.org API latency |
| `search()` (cached, same process) | ~0.1 ms | Cache hit |
| `search()` (cached, restart) | ~0.2 ms | Disk cache load + hit |
| `open_window()` (snacks) | ~5 ms | Window creation |
| `open_window()` (native) | ~3 ms | Buffer + window creation |
| Budoux parse (single line, first) | ~2-5 ms | Japanese text segmentation |
| Budoux parse (cached) | ~0.01 ms | Boundary cache hit |

---

## 8. Known Optimizations (Implemented)

| Optimization | Location | Status |
|--------------|----------|--------|
| Budoux boundary caching per line per buffer | `ui.lua` | ✅ Auto-invalidated on buffer change |
| Single-pass URL encoding | `core.lua` | ✅ 1 `gsub` with capture function |
| In-memory search cache with 5min TTL | `core.lua` | ✅ |
| Persistent disk cache | `core.lua` | ✅ `~/.cache/nvim/jisho_cache.json` |
| Request deduplication | `core.lua` | ✅ In-flight tracking |
| Localized globals | All files | ✅ |
| `vim.uv`/`vim.system` in hot paths | `core.lua` | ✅ |
| `vim_bo`/`vim_wo` instead of deprecated APIs | All files | ✅ Neovim 0.13+ compatible |

---

## 9. Development Workflow

### Test Commands

```bash
# Quick smoke test
nvim --headless -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup()" -c "qall"

# Test search (requires network)
nvim --headless -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup(); require('jisho').search('食べる')" -c "qall"

# Test native fallback (no snacks)
nvim --headless -c "lua package.loaded['snacks']=nil" -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup({use_snacks=false})" -c "qall"

# Test history
nvim --headless -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup(); require('jisho').history()" -c "qall"

# Benchmark startup
for i in {1..10}; do nvim --headless -u NONE -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup()" -c "qall"; done 2>&1 | tail -5

# LSP diagnostics
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/core.lua
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/ui.lua
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/init.lua
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/style.lua
```

---

## 10. Critical Patterns & Conventions

### HTTP Request Patterns

```lua
local vim_net_request = vim.net and vim.net.request
if vim_net_request then
  local query_url = url .. '?keyword=' .. urlencode(word)
  vim_net_request(query_url, {}, function(err, response)
    if err then process_response(err, nil) else process_response(nil, response and response.body) end
  end)
else
  vim_system({ 'curl', '-s', '-G', '--data-urlencode', 'keyword=' .. word, url }, { text = true }, callback)
end
```

### Async Pattern

```lua
vim_schedule(function()
  vim_notify('Query successful', ...)
  require('jisho.ui').open_window(lines, title, config)
end)
```

### Optional Dependencies

```lua
local ok, snacks = pcall(require, 'snacks')
if not ok then return end
```

### Localized Globals

```lua
local string_format = string.format
local string_byte = string.byte
local string_gsub = string.gsub
local table_concat = table.concat
local math_min = math.min
local pcall = pcall
local os_time = os.time
local uv = vim.uv
local io_open = io.open
local vim_fs_normalize = vim.fs.normalize

local vim_notify = vim.notify
local vim_schedule = vim.schedule
local vim_fn_expand = vim.fn.expand
local vim_trim = vim.trim
local vim_log_levels = vim.log.levels
local vim_json_decode = vim.json.decode
local vim_json_encode = vim.json.encode
local vim_net_request = vim.net and vim.net.request
local vim_system = vim.system
local vim_api = vim.api
local vim_bo = vim.bo
local vim_wo = vim.wo
```

### Modern Option APIs (Neovim 0.13+)

```lua
-- Use vim_bo/vim_wo instead of deprecated nvim_buf/win_set_option
vim_bo[buf].filetype = 'markdown'
vim_bo[buf].modifiable = false
vim_wo[win].wrap = true
vim_wo[win].conceallevel = 2
```

---

## 11. Common Tasks

### Add New Layout Type

1. `style.lua`: Add function to `M.layouts` table
2. `style.lua`: Handle fallback in `M.spacer()`
3. `init.lua`: Document in config type hints (`---@class JishoConfig`)

### Modify Search Results Display

1. `core.lua`: Modify `build_lines(item, config)` function
2. `style.lua`: Adjust spacer behavior if needed
3. Test with various Jisho.org result structures

### Add New HTTP Client

1. `core.lua`: Add detection in `M.search()` before `vim_net_request` check
2. Implement `process_response(word, config, callbacks, err, json_str)` signature
3. Test with Neovim version lacking target API

### Add UI Action

1. `ui.lua`: Add keymap in `open_window()` in both snacks and native paths
2. Implement handler function

### Add History Entry

```lua
add_to_history(word, timestamp)
save_cache()
```

---

## 12. Known Limitations / Gotchas

| Issue | Location | Notes |
|-------|----------|-------|
| Max 5 results hardcoded | `core.lua` | `local len = math_min(5, #data)` |
| No pitch/accent data | Jisho API | Not provided by API |
| Cache TTL 5min fixed | `core.lua` | `CACHE_TTL = 300` |
| History max 100 entries | `core.lua` | `MAX_HISTORY = 100` |
| `curl` fallback spawns process | `core.lua` | Neovim 0.10+ preferred |
| Requires internet | — | No offline mode |

---

## 13. Debugging Checklist

| Symptom | Check |
|---------|-------|
| Search fails silently | `:messages` for `vim.notify` output; check `process_response` error path |
| UI doesn't open | `snacks` available? `nvim_open_win` valid? Check `JishoWindowOpened` autocmd |
| Budoux jumps don't work | `budoux` installed? Line contains UTF-8? `string_find(line, "[\128-\255]")` |
| Slow startup | Module load time — localize globals (already done) |
| Encoding issues | `urlencode` handles spaces, newlines, non-ASCII? Test `食べる` |
| Native window looks wrong | `vim_wo` options: `conceallevel=2`, `wrap=true`, `cursorline=true` |
| `curl` not found | System `curl` in PATH? Neovim 0.10+ has native HTTP |
| Cache not persisting | `~/.cache/nvim/jisho_cache.json` writable? `save_cache` called? |
| History empty | `search_history` populated? `add_to_history` called? |
| Deduplication not working | `in_flight[word]` set before request? |
| Spinner stuck | `stop_spinner()` called? Timer closed? |

---

## 14. Sync Locations

| Source (Edit Here) | Installed (Test Here) |
|--------------------|----------------------|
| `/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/` | `~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/` (via `vim.pack.add`) |

**Test in installed location** — that's what users run.

---

## 15. Recent Changes (2026-08-17)

### Major Features Added

- **Enhanced Results**: Other forms, tags, sense info/notes, see_also, sense tags
- **Search History**: `:JishoHistory` command with timestamps, Enter to re-search
- **j/k Navigation**: Jump between senses/entries in result window
- **Persistent Cache**: Disk cache at `~/.cache/nvim/jisho_cache.json`, survives restarts
- **Request Deduplication**: In-flight tracking prevents duplicate API calls
- **Modern APIs**: `vim_bo`/`vim_wo` instead of deprecated `nvim_buf/win_set_option`

### Performance Optimizations

- Budoux boundary caching (per line, per buffer, auto-invalidated)
- Single-pass URL encoding
- In-memory cache with 5min TTL
- Request deduplication

---

*Generated 2026-08-17. Follows resonance.nvim knowledge base pattern. Updated with all new features: enhanced results, search history, j/k navigation, persistent disk cache, request deduplication, modern vim_bo/vim_wo APIs.*