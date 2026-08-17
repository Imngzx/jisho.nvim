# jisho.nvim — AI Agent Knowledge Base

> **Purpose**: Enable future AI agents to work on this codebase without re-discovering patterns.  
> **Last Updated**: 2026-08-17

---

## 1. Module Map

| File | Responsibility |
|------|----------------|
| `lua/jisho/init.lua` | Public API: `setup()`, `search()`, user command `:Jisho` |
| `lua/jisho/core.lua` | Search logic: URL encoding, HTTP request, response parsing, line generation |
| `lua/jisho/ui.lua` | Window creation: snacks.nvim integration, native fallback, Budoux jumps |
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

### Search Flow (`core.lua:35-125`)

```lua
M.search(word, config)
  → if not word: word = vim_fn_expand('<cword>')
  → word = trim + collapse whitespace
  → urlencode(word)  -- 3-pass gsub (perf: see §5)
  → vim_notify('Searching...')
  → HTTP request:
      vim_net_request (Neovim 0.10+)  -- native, async
      OR vim_system('curl') fallback -- subprocess
  → process_response(err, json_str)
    → pcall(vim_json_decode)
    → build lines[] table (max 5 results)
      → word_jp + reading + is_common + jlpt
      → senses: english_definitions + parts_of_speech
      → style.spacer(layout) between entries
    → vim_schedule(open_window)
```

### URL Encoding (`core.lua:23-33`)

```lua
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
```

**Performance note**: 3 separate `string.gsub` passes. Single-pass possible.

### UI Rendering (`ui.lua:81-175`)

```lua
M.open_window(lines, title, config)
  → Plan A: snacks.nvim
      if config.use_snacks and snacks available:
        snacks.win({ text=lines, width, height, border, title, bo, wo, keys })
        setup_budoux_jumps(buf, config)
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
  → Both: fire User JishoWindowOpened autocmd
```

### Budoux Word Jumps (`ui.lua:25-79`)

```lua
setup_budoux_jumps(buf, config)
  → if not config.use_budoux: return
  → pcall(require, 'budoux')
  → M._budoux_parser = budoux.load_japanese_model()  -- cached module-level
  → jump(dir)  -- 'w' or 'b'
      cursor = nvim_win_get_cursor(0)
      line = nvim_buf_get_lines(buf, row-1, row, false)[1]
      if no UTF-8 in line: fallback to normal! w/b
      segments = M._budoux_parser.parse(line)
      boundaries = {1}
      for segment in segments: boundaries[#boundaries+1] = current + #segment
      find next/prev boundary relative to cursor col
      nvim_win_set_cursor(0, {row, boundary-1})
      fallback: normal! w/b
  → bind 'w'/'b' to jump('w')/jump('b')
```

**Performance issue**: Re-parses line on every keystroke. Should cache boundaries per line number.

---

## 3. UI State

No persistent UI state module — state is ephemeral per window:
- `M._budoux_parser` — module-level cache for Budoux parser
- Window/buffer created fresh per search
- No `view_mode`, `expanded`, or similar state

---

## 4. Rendering Pipeline

Simple: `core.lua` builds `lines[]` array → `ui.lua` passes to `snacks.win` or `nvim_buf_set_lines`.

No complex rendering like resonance's DAG view.

---

## 5. Performance Baselines (2026-08-17)

| Operation | Avg Time | Notes |
|-----------|----------|-------|
| `require('jisho')` | ~0.5 ms | Cold require |
| `setup()` | ~0.1 ms | Config merge only |
| `search()` (network) | ~200-500 ms | Jisho.org API latency |
| `search()` (local processing) | ~1 ms | JSON decode + line building |
| `open_window()` (snacks) | ~5 ms | Window creation |
| `open_window()` (native) | ~3 ms | Buffer + window creation |
| Budoux parse (single line) | ~2-5 ms | Japanese text segmentation |
| `vim_net_request` call | ~1-2 ms | Native HTTP |
| `vim_system('curl')` call | ~50-100 ms | Subprocess overhead |

### Known Bottlenecks

| Issue | Location | Impact | Fix |
|-------|----------|--------|-----|
| Budoux re-parse on every `w`/`b` | `ui.lua:34-75` | ~2-5ms per keystroke | Cache boundaries per line number |
| URL encoding: 3 `gsub` passes | `core.lua:27-33` | ~0.01 ms per word | Single-pass with capture function |
| `curl` subprocess fallback | `core.lua:115-124` | ~50-100 ms vs ~2 ms | Require Neovim 0.10+; warn otherwise |

---

## 6. Development Workflow

### Test Commands

```bash
# Quick smoke test
nvim --headless -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup()" -c "qall"

# Test search (requires network)
nvim --headless -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup(); require('jisho').search('食べる')" -c "qall"

# Test native fallback (no snacks)
nvim --headless -c "lua package.loaded['snacks']=nil" -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup({use_snacks=false})" -c "qall"

# Benchmark startup
for i in {1..10}; do nvim --headless -u NONE -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup()" -c "qall"; done 2>&1 | tail -5

# LSP diagnostics
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/core.lua
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/ui.lua
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/init.lua
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/style.lua
```

---

## 7. Critical Patterns & Conventions

### HTTP Request Patterns

```lua
-- Primary: vim.net.request (Neovim 0.10+)
local vim_net_request = vim.net and vim.net.request
if vim_net_request then
  local query_url = url .. '?keyword=' .. urlencode(word)
  vim_net_request(query_url, { method='GET', headers={Accept='application/json'} }, callback)
else
  -- Fallback: vim.system with curl
  vim_system({ 'curl', '-s', '-G', '--data-urlencode', 'keyword=' .. word, url }, { text = true }, callback)
end
```

### Async Pattern

All HTTP is async → `vim_schedule` for UI updates:

```lua
vim_schedule(function()
  vim_notify('Query successful', ...)
  require('jisho.ui').open_window(lines, title, config)
end)
```

### Optional Dependencies

```lua
local ok, snacks = pcall(require, 'snacks')
if not ok then return end  -- graceful degradation
```

### Localized Globals (at module top)

```lua
local string_format = string.format
local string_byte = string.byte
local string_gsub = string.gsub
local table_concat = table.concat
local math_min = math.min
local pcall = pcall
-- vim APIs
local vim_notify = vim.notify
local vim_schedule = vim.schedule
local vim_json_decode = vim.json.decode
local vim_net_request = vim.net and vim.net.request
local vim_system = vim.system
```

---

## 8. Common Tasks

### Add New Layout Type

1. `style.lua`: Add function to `M.layouts` table
2. `style.lua`: Handle fallback in `M.spacer()`
3. `init.lua`: Document in config type hints (`---@class JishoConfig`)

### Modify Search Results Display

1. `core.lua`: Modify `process_response()` line building (lines 68-99)
2. `style.lua`: Adjust spacer behavior if needed
3. Test with various Jisho.org result structures (single/multiple senses, missing fields)

### Add New HTTP Client

1. `core.lua`: Add detection in `M.search()` before `vim_net_request` check
2. Implement `process_response` callback signature: `(err, json_str) -> nil`
3. Test with Neovim version lacking target API

### Add UI Action (e.g., copy word, open in browser)

1. `ui.lua`: Add keymap in `open_window()` after line 165
2. Implement handler function (may need `vim.fn.setreg` or `vim.ui.open`)
3. Works for both snacks and native paths — add in both code paths

### Optimize Budoux Jumps (Performance)

1. Add module-level cache: `local budoux_cache = {}  -- [line_num] = {boundaries={}, text=""}`
2. In `jump()`: check cache before parsing, invalidate on buffer change
3. Use `vim.api.nvim_buf_attach(buf, false, {on_lines = function() budoux_cache = {} end})`

### Single-Pass URL Encoding

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

---

## 9. Known Limitations / Gotchas

| Issue | Location | Notes |
|-------|----------|-------|
| Max 5 results hardcoded | `core.lua:70` | `local len = math_min(5, #data)` |
| No cache for search results | — | Each search hits API |
| Budoux re-parse per keystroke | `ui.lua:45` | Should cache per line |
| URL encoding 3-pass | `core.lua:27-33` | Single-pass possible |
| `curl` fallback spawns process | `core.lua:115-124` | Blocking-ish; Neovim 0.10+ preferred |
| No spec parsing from Jisho.org | — | Only uses public API |
| No offline mode | — | Requires internet |

---

## 10. Recent Changes (2026-08-17)

### Created Documentation

- **AGENTS.md** — AI development guidelines with benchmarks, workflow, patterns
- **note/knowledge/jisho.nvim.md** — This knowledge base

---

## 11. Quick Reference: Adding Features

### New Layout Type

1. `style.lua`: `M.layouts.my_layout = function(lines) ... end`
2. `style.lua`: `M.spacer` fallback already handles unknown layouts
3. `init.lua`: Add to `JishoConfig` type hint

### New UI Action

1. `ui.lua`: Add keymap in `open_window()` (both snacks and native paths)
2. Implement handler (may need access to `word` — pass via closure or buffer var)

### New HTTP Client

1. `core.lua`: Add detection before `vim_net_request` check
2. Match callback signature: `function(err, json_str) ... end`

---

## 12. Debugging Checklist

| Symptom | Check |
|---------|-------|
| Search fails silently | `:messages` for `vim.notify` output; check `process_response` error path |
| UI doesn't open | `snacks` available? `nvim_open_win` valid? Check `JishoWindowOpened` autocmd |
| Budoux jumps don't work | `budoux` installed? Line contains UTF-8? `string_find(line, "[\128-\255]")` |
| Slow startup | Module load time — localize globals, lazy-require (already done) |
| Encoding issues | `urlencode` handles spaces, newlines, non-ASCII? Test `食べる` |
| Native window looks wrong | `vim_wo` options: `conceallevel=2`, `wrap=true`, `cursorline=true` |
| `curl` not found | System `curl` in PATH? Neovim 0.10+ has native HTTP |

---

## 13. Sync Locations

| Source (Edit Here) | Installed (Test Here) |
|--------------------|----------------------|
| `/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/` | `~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/` (via `vim.pack.add`) |

**Test in installed location** — that's what users run.

---

*Generated 2026-08-17. Follows resonance.nvim knowledge base pattern.*