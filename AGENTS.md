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
| `lua/jisho/init.lua` | Public API: `setup()`, `search()`, user command `Jisho` |
| `lua/jisho/core.lua` | Search logic: URL encoding, HTTP request, response parsing, line generation |
| `lua/jisho/ui.lua` | Window creation: snacks.nvim integration, native fallback, Budoux jumps |
| `lua/jisho/style.lua` | Layout functions: `spacious`, `compact`, `super_spacious` spacing |

### Search Flow (`core.lua`)

```lua
M.search(word, config)
  → word = word or <cword>
  → urlencode(word)
  → vim_notify('Searching...')
  → vim.net.request (Neovim 0.10+) OR vim.system('curl') fallback
  → process_response(err, json_str)
    → vim.json.decode
    → build lines table (max 5 results)
      → word + reading + common + jlpt
      → senses with english_definitions + parts_of_speech
      → style.spacer(layout) between entries
    → vim_schedule(open_window)
```

### UI Rendering (`ui.lua`)

```lua
M.open_window(lines, title, config)
  → Plan A: snacks.nvim (if config.use_snacks and snacks available)
      snacks.win({ text=lines, width, height, border, title, bo, wo, keys })
      setup_budoux_jumps(buf, config)
  → Plan B: native nvim_open_win
      nvim_create_buf → nvim_buf_set_lines → nvim_open_win
      setup_budoux_jumps(buf, config)
  → Both: User JishoWindowOpened autocmd
```

### Budoux Word Jumps (`ui.lua:34-75`)

- Caches parser: `M._budoux_parser = budoux.load_japanese_model()` (once)
- On `w`/`b` keypress: parses current line, finds boundaries, moves cursor
- **Performance issue**: re-parses line on every keystroke (see §5)

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
if vim_net_request then
  vim_net_request(query_url, { method='GET', headers={Accept='application/json'} }, callback)
else
  -- Fallback: vim.system with curl
  vim_system({ 'curl', '-s', '-G', '--data-urlencode', 'keyword=' .. word, url }, { text = true }, callback)
end
```

### Performance Rules

- **No filesystem walks** — this is a dictionary lookup plugin
- **Localize globals at top**: `local string_gsub = string.gsub`, `local vim_schedule = vim.schedule`
- **Use `vim.uv`/`vim.system` over `vim.fn`** in hot paths
- **`vim.schedule()` for async UI updates** — never block on HTTP
- **Batch `nvim_buf_set_lines`** — single call with all lines (already done)

### Lua Style (Project Conventions)

- Tables over multiple returns
- Early returns, flat conditionals
- Comments only for *why*, not *what*
- `pcall` for optional dependencies (`snacks`, `budoux`)
- Use `math_min`, `table_concat`, `string_format` locals

---

## 6. Common Tasks

### Add New Layout Type

1. `style.lua`: Add function to `M.layouts` table
2. `style.lua`: Handle fallback in `M.spacer()`
3. `init.lua`: Document in config type hints

### Modify Search Results Display

1. `core.lua`: Modify `process_response()` line building (lines 68-99)
2. `style.lua`: Adjust spacer behavior if needed
3. Test with various Jisho.org result structures

### Add New HTTP Client

1. `core.lua`: Add detection in `M.search()` before `vim_net_request` check
2. Implement `process_response` callback signature
3. Test with Neovim version lacking target API

### Add UI Action (e.g., copy word, open in browser)

1. `ui.lua`: Add keymap in `open_window()` after line 165
2. Implement handler function (may need `vim.fn.setreg` or `vim.ui.open`)
3. Works for both snacks and native paths

---

## 7. Performance Baselines (2026-08-17)

| Operation | Avg Time | Notes |
|-----------|----------|-------|
| Module load (`require('jisho')`) | ~0.5 ms | Cold require |
| `setup()` | ~0.1 ms | Config merge only |
| `search()` (network) | ~200-500 ms | API latency dominant |
| `search()` (local processing) | ~1 ms | JSON decode + line building |
| `open_window()` (snacks) | ~5 ms | Window creation |
| `open_window()` (native) | ~3 ms | Buffer + window creation |
| Budoux parse (single line) | ~2-5 ms | Japanese text segmentation |

**Known bottlenecks:**
- Budoux re-parsing on every `w`/`b` keystroke — cache boundaries per line
- URL encoding does 3 `string.gsub` passes — single-pass possible
- `curl` subprocess fallback — avoid by requiring Neovim 0.10+

---

## 8. Debugging Checklist

| Symptom | Check |
|---------|-------|
| Search fails silently | `vim.notify` history (`:messages`), check `process_response` error path |
| UI doesn't open | `snacks` available? `nvim_open_win` valid? Check `JishoWindowOpened` autocmd |
| Budoux jumps don't work | `budoux` installed? Line contains UTF-8? `string_find(line, "[\128-\255]")` |
| Slow startup | Module load time — localize globals, lazy-require |
| Encoding issues | `urlencode` handles spaces, newlines, non-ASCII? Test `食べる` |
| Native window looks wrong | `vim_wo` options: `conceallevel=2`, `wrap=true`, `cursorline=true` |

---

## 9. Reference: APIs Used

| API | Purpose | Location |
|-----|---------|----------|
| `vim.net.request` | Native HTTP (Neovim 0.10+) | `core.lua:110` |
| `vim.system` | Subprocess fallback (curl) | `core.lua:115` |
| `vim.json.decode` | Parse Jisho API response | `core.lua:60` |
| `vim.api.nvim_create_buf` | Create result buffer | `ui.lua:123` |
| `vim.api.nvim_buf_set_lines` | Set buffer content | `ui.lua:124` |
| `vim.api.nvim_open_win` | Open floating window | `ui.lua:144` |
| `vim.keymap.set` | Bind `q`/`Esc`/`w`/`b` | `ui.lua:77,165,166` |
| `vim.system`/`vim.net.request` | Async, non-blocking | Required for UI responsiveness |

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

*Generated 2026-08-17. Follows resonance.nvim AGENTS.md pattern.*