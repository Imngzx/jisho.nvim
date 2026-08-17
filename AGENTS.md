# jisho.nvim — AI Development Guidelines

> **Purpose**: Step-by-step reference for AI assistants working on this codebase.  
> **Audience**: Any AI agent (Cursor, Claude, Copilot, etc.) editing `jisho.nvim`.  
> **Last Updated**: 2026-08-17

---

## 1. Repository Overview

| Aspect | Detail |
|--------|--------|
| **Type** | Neovim plugin — async Japanese dictionary lookup via Jisho.org API |
| **Entry Point** | `lua/jisho/init.lua` → `require('jisho').setup()` |
| **Core Modules** | `core.lua` (search/API), `ui.lua` (window rendering), `style.lua` (layouts) |
| **Install Location** | `vim.pack.add('https://github.com/Imngzx/jisho.nvim')` |
| **Config Style** | Single `setup(opts)` with optional `use_snacks`, `use_budoux`, `layout`, `window` |
| **Requirements** | Neovim >= 0.10 (uses `vim.system`, `vim.net.request`), `curl` fallback |

---

## 2. Available Tools on This Machine

| Tool | Path | Purpose |
|------|------|---------|
| `nvim` | System `nvim` (0.10+) | Headless testing: `nvim --headless -c "..." -c "qall"` |
| `lua` | Embedded in `nvim` | All Lua execution via `nvim --headless -c "lua ..."` |
| `rg` (ripgrep) | System `rg` | Fast code search |
| `git` | System `git` | Version control |
| `bash` / `fish` | Standard | Shell commands, pipelines |
| `lua-language-server` | `/usr/bin/lua-language-server` (pacman) | LSP diagnostics: `lua-language-server --check=FILE` |
| `curl` | System `curl` | HTTP fallback for Neovim < 0.12 |

### Benchmark Command Template

```bash
# Startup benchmark (10 runs, 3 warmup, no user config)
nvim --headless -u NONE -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup()" -c "qall"

# Search latency (mock or real)
nvim --headless -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup(); local t=vim.uv.hrtime(); require('jisho').search('食べる'); vim.wait(2000); print('search:', (vim.uv.hrtime()-t)/1e6, 'ms')" -c "qall"

# Direct function timing
nvim --headless -c "lua local t=vim.uv.hrtime(); require('jisho.core').search('test', {}); vim.wait(2000); print('core:', (vim.uv.hrtime()-t)/1e6, 'ms')" -c "qall"

# LSP diagnostics
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/core.lua
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/ui.lua
```

---

## 3. Key Architecture Patterns

### Module Map

| File | Responsibility |
|------|----------------|
| `lua/jisho/init.lua` | Public API: `setup()`, `search()`, `history()`, user commands `Jisho`, `JishoHistory` |
| `lua/jisho/core.lua` | Search logic: URL encoding, HTTP request, response parsing, line generation, caching, history, deduplication |
| `lua/jisho/ui.lua` | Window creation: snacks.nvim integration, native fallback, Budoux jumps, j/k navigation |
| `lua/jisho/style.lua` | Layout functions: `spacious`, `compact`, `super_spacious` spacing |

### Search Flow (`core.lua`)

```lua
M.search(word, config)
  → word = word or <cword>
  → word = trim + collapse whitespace
  → Check in-memory cache (5min TTL)
  → Check in-flight deduplication
  → Start spinner (vim.notify with Braille animation)
  → HTTP request:
      vim.net.request (Neovim 0.10+)  -- native, async
      OR vim.system('curl') fallback -- subprocess
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

### UI Rendering (`ui.lua`)

```lua
M.open_window(lines, title, config)
  → Plan A: snacks.nvim (if config.use_snacks and snacks available)
      snacks.win({ text=lines, width, height, border, title, bo, wo, keys })
      setup_budoux_jumps(buf, config)
      setup_navigation(buf, win, lines)  -- j/k between senses/entries
      return
  → Plan B: native nvim_open_win
      nvim_create_buf → nvim_buf_set_lines → nvim_open_win
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

---

## 4. Development Workflow

### Step 1: Read & Understand

```bash
# Read core modules
read lua/jisho/init.lua
read lua/jisho/core.lua
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

### Step 4: Verify

```bash
# Functional tests
nvim --headless -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup(); require('jisho').search('test')" -c "qall"
nvim --headless -c "lua package.loaded['snacks']=nil" -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup({use_snacks=false}); require('jisho').search('test')" -c "qall"
nvim --headless -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup(); require('jisho').history()" -c "qall"

# LSP diagnostics
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/core.lua
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/ui.lua
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/init.lua
lua-language-server --check=/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/style.lua

# Startup regression check
nvim --headless -u NONE -c "luafile lua/jisho/init.lua" -c "lua require('jisho').setup()" -c "qall"  # must complete < 50ms
```

### Step 5: Commit

```bash
cd /home/alice/Projects/code/lua/jisho.nvim
git add lua/jisho/*.lua
git commit -m "feat(core): add single-pass URL encoding"
```

---

## 5. Critical Patterns & Conventions

### HTTP Request Patterns

```lua
-- Primary: vim.net.request (Neovim 0.10+)
local vim_net_request = vim.net and vim.net.request
if vim_net_request then
  local query_url = url .. '?keyword=' .. urlencode(word)
  vim_net_request(query_url, {}, function(err, response)
    if err then process_response(err, nil) else process_response(nil, response and response.body) end
  end)
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

---

## 6. Common Tasks

### Add New Layout Type

1. `style.lua`: Add function to `M.layouts` table
2. `style.lua`: Handle fallback in `M.spacer()`
3. `init.lua`: Document in config type hints (`---@class JishoConfig`)

### Modify Search Results Display

1. `core.lua`: Modify `build_lines()` function (handles other forms, tags, senses, info)
2. `style.lua`: Adjust spacer behavior if needed
3. Test with various Jisho.org result structures (single/multiple senses, missing fields)

### Add New HTTP Client

1. `core.lua`: Add detection in `M.search()` before `vim_net_request` check
2. Implement `process_response` callback signature: `(word, config, callbacks, err, json_str) -> nil`
3. Test with Neovim version lacking target API

### Add UI Action (e.g., copy word, open in browser)

1. `ui.lua`: Add keymap in `open_window()` in both snacks and native paths
2. Implement handler function (may need `vim.fn.setreg` or `vim.ui.open`)

### Add History Entry

1. Call `add_to_history(word, timestamp)` — auto-deduplicates, trims to 100 entries
2. Call `save_cache()` — scheduled, writes to `~/.cache/nvim/jisho_cache.json`

---

## 7. Performance Baselines (2026-08-17)

| Operation | Avg Time | Notes |
|-----------|----------|-------|
| Module load (`require('jisho')`) | ~0.5 ms | Cold require |
| `setup()` | ~0.5 ms | Config merge + cache load |
| `search()` (network, first) | ~3000-4000 ms | Jisho.org API latency |
| `search()` (cached, same process) | ~0.1 ms | Cache hit |
| `search()` (cached, restart) | ~0.2 ms | Disk cache load + hit |
| `open_window()` (snacks) | ~5 ms | Window creation |
| `open_window()` (native) | ~3 ms | Buffer + window creation |
| Budoux parse (single line, first) | ~2-5 ms | Japanese text segmentation |
| Budoux parse (cached) | ~0.01 ms | Boundary cache hit |

### Known Optimizations (Implemented)

- ✅ Budoux boundary caching per line per buffer (auto-invalidated)
- ✅ Single-pass URL encoding (1 `gsub` with capture function)
- ✅ In-memory search cache with 5min TTL
- ✅ Persistent disk cache (`~/.cache/nvim/jisho_cache.json`)
- ✅ Request deduplication (in-flight tracking)
- ✅ Localized globals, `vim.uv`/`vim.system` in hot paths
- ✅ `vim_bo`/`vim_wo` instead of deprecated `nvim_buf/win_set_option`

---

## 8. Debugging Checklist

| Symptom | Check |
|---------|-------|
| Search fails silently | `:messages` for `vim.notify` output; check `process_response` error path |
| UI doesn't open | `snacks` available? `nvim_open_win` valid? Check `JishoWindowOpened` autocmd |
| Budoux jumps don't work | `budoux` installed? Line contains UTF-8? `string_find(line, "[\128-\255]")` |
| Slow startup | Module load time — localize globals, lazy-require (already done) |
| Encoding issues | `urlencode` handles spaces, newlines, non-ASCII? Test `食べる` |
| Native window looks wrong | `vim_wo` options: `conceallevel=2`, `wrap=true`, `cursorline=true` |
| `curl` not found | System `curl` in PATH? Neovim 0.10+ has native HTTP |
| Cache not persisting | `~/.cache/nvim/jisho_cache.json` writable? `vim.fn.mkdir` in `save_cache` |
| History empty | `search_history` populated? `add_to_history` called? |
| Deduplication not working | `in_flight[word]` set before request? |

---

## 9. Reference: APIs Used

| API | Purpose | Location |
|-----|---------|----------|
| `vim.net.request` | Native HTTP (Neovim 0.10+) | `core.lua` |
| `vim.system` | Subprocess fallback (curl) | `core.lua` |
| `vim.json.decode` / `encode` | Parse/serialize JSON | `core.lua` |
| `vim.api.nvim_create_buf` | Create result buffer | `ui.lua`, `core.lua` (history) |
| `vim.api.nvim_buf_set_lines` | Set buffer content | `ui.lua`, `core.lua` |
| `vim.api.nvim_open_win` | Open floating window | `ui.lua`, `core.lua` |
| `vim.api.nvim_buf_attach` | Invalidate Budoux cache | `ui.lua` |
| `vim.keymap.set` | Bind `q`/`Esc`/`w`/`b`/`j`/`k`/`<CR>` | `ui.lua`, `core.lua` |
| `vim.uv.new_timer` | Spinner animation | `core.lua` |
| `vim.fn.stdpath('cache')` | Cache directory | `core.lua` |
| `vim.bo` / `vim.wo` | Buffer/window options (modern) | `ui.lua`, `core.lua` |

---

## 10. Sync Locations

| Source (Edit Here) | Installed (Test Here) |
|--------------------|----------------------|
| `/home/alice/Projects/code/lua/jisho.nvim/lua/jisho/` | `~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/` (via `vim.pack.add`) |

**Test in installed location** — that's what users run.

---

## 11. Emergency: Restore Original Files

```bash
# From git HEAD
cd /home/alice/Projects/code/lua/jisho.nvim
git show HEAD:lua/jisho/core.lua > ~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/core.lua
git show HEAD:lua/jisho/ui.lua > ~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/ui.lua
git show HEAD:lua/jisho/init.lua > ~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/init.lua
git show HEAD:lua/jisho/style.lua > ~/.local/share/nvim/site/pack/core/opt/jisho.nvim/lua/jisho/style.lua
```

---

## 12. AI Workflow & Communication Patterns

### Todo System (Mandatory for Multi-Step Work)

**Initialize at start of any multi-step task:**

```lua
todo(i="Brief purpose", op="init", list=[{"phase": "PhaseName", "items": ["Task 1", "Task 2"]}])
```

**Update as work progresses:**

```lua
todo(i="Task description", op="start", task="Task 1", phase="PhaseName")
todo(i="Task description", op="done", task="Task 1", phase="PhaseName")
```

**Phase transitions are automatic** — earliest incomplete task in phase order becomes active.

---

*Generated 2026-08-17. Follows resonance.nvim AGENTS.md pattern. Updated with all new features: enhanced results (other forms, tags, info), search history (:JishoHistory), j/k navigation, persistent disk cache, request deduplication, modern vim_bo/vim_wo APIs.*