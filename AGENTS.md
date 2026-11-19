# jisho.nvim — AI Development Guidelines

> **Purpose:** the hard rules for editing this codebase. Read it, then read
> the source — the source wins.
> **Target:** Neovim **0.13+** (`vim.async`, `vim.net.request`).
> repo url [jisho.nvim](https://github.com/Imngzx/jisho.nvim).

---

## 1. Project structure

| Path | Role |
|---|---|
| `lua/jisho/init.lua` | Public API: `setup()`, `search()`, `history()`; defines the `:Jisho*` user commands at require time |
| `lua/jisho/core/init.lua` | Re-exports `setup`, `search`, `history`, `build_lines` |
| `lua/jisho/core/cache.lua` | All shared state: result cache, history, in-flight table, spinner, URL encoding, disk persistence |
| `lua/jisho/core/search.lua` | Search flow: normalize word, cache hit, dedupe, async HTTP, process response |
| `lua/jisho/core/response.lua` | `build_lines(item, cfg)`: one Jisho API entry → Markdown lines |
| `lua/jisho/core/history.lua` | `:JishoHistory` (snacks.picker, native float fallback) |
| `lua/jisho/core/dedupe.lua` | `:JishoDedupe` / `:JishoRefresh` handlers, kana-normalized key lookup |
| `lua/jisho/ui.lua` | Result window (snacks.win or native float), `j`/`k` navigation, Budoux `w`/`b` |
| `lua/jisho/style.lua` | Layout spacers: `compact`, `spacious`, `super_spacious` |

How the pieces fit together: `ARCHITECTURE.md`. User docs: `README.md`,
`doc/jisho.txt`.

**Tools:** `rg` and `fd` over `grep`/`find`; `nvim --headless` for testing;
`lua-language-server --check=FILE` for diagnostics.

**Open issues live in GitHub Issues.** History is `git log`; the *why* of
a fix lives in code comments. Keep any working plan in an untracked file
(for example via `.git/info/exclude`) and do not commit it.

---

## 2. Red lines — violating these causes bugs

1. **Schedule everything that leaves a callback.** `vim.net.request` and
   `vim.system` callbacks run in a fast-event context: wrap `done(...)`,
   `vim.notify`, and UI work in `vim.schedule`.
2. **Never return the request/job handle from a `vim.async.await` adapter,**
   and never use positional `await(argc, fn, ...)` with `vim.net.request` or
   `vim.system`. `vim.async` closes a returned handle on completion, which
   kills the request; positional await assumes a success-only callback and
   mangles their error-first results. Adapt explicitly (see `request()` in
   `core/search.lua`).
3. **Cache lookup and `in_flight[word]` dedupe happen before `vim.async.run`.**
   An entry is `{ callbacks, task }`; completion clears it only if
   `in_flight[word]` is still that same entry.
4. **Only the matching search stops the spinner.** `start_spin()` returns an
   epoch; `stop_spin(..., epoch)` advances it only if it is still current.
   No `uv.new_timer` — the spinner is an async task using `vim.async.sleep(80)`.
5. **Keep both transports.** Native `vim.net.request` (retry = 3) and the
   `curl` fallback stay until the supported Neovim range changes.
6. **Shared state lives in `core/cache.lua`.** Other modules read it through
   the module table (`c.search_cache`, `c.in_flight`, `c.hist`); `cache.lua`
   itself uses upvalues, so reassigning a field from outside (`c.x = {}`)
   desyncs the two. Clear tables in place instead.
7. **Requiring `jisho` must stay cheap.** `vim.async` is resolved lazily
   (`ensure_async()`); do not pull heavy modules into `init.lua` at load.

---

## 3. Code style — match the surrounding code

- **Localize what the module uses, at the top.** Follow the naming already in
  that file: most modules use short aliases (`sfmt`, `sgsub`, `vsched`,
  `vnotif`, `vlog`, `nwin_sc`, `vbo`/`vwo`); `core/history.lua` uses long
  ones (`string_format`, `vim_schedule`). No unused aliases.
- **Arrays → numeric `for i = 1, #t`. Dictionaries → `pairs()`.** No
  `ipairs()` or `vim.iter()`.
- **Line building uses a manual index** (`lines[li] = x; li = li + 1`).
  `spacer()` appends through `#lines`, so resync with `li = #lines + 1`
  after calling it.
- `vim.bo[buf]` / `vim.wo[win]`, never `nvim_buf_set_option`.
- Early returns, flat conditionals, comments only for *why*.

---

## 4. Development loop

Test the working tree, not the installed copy, and point the cache at a
temp dir so runs never touch the real `~/.cache/nvim/jisho_cache.json`:

```bash
X=$(mktemp -d)
J="env XDG_CACHE_HOME=$X nvim --headless -u NONE --cmd 'set rtp^=.'"
WAIT="vim.wait(15000, function() return #vim.api.nvim_list_wins() > 1 end); print(#vim.api.nvim_list_wins())"

# native request (prints 2 when the window opened)
eval $J -c "\"lua require('jisho').setup({use_snacks=false}); require('jisho').search('食べる'); $WAIT\"" -c qall
# curl fallback
eval $J -c "\"lua vim.net=nil\"" -c "\"lua require('jisho').setup({use_snacks=false}); require('jisho').search('猫'); $WAIT\"" -c qall
rm -rf "$X"
```

After changing the search/async flow, also cover a **cache hit** (search the
same word twice in one process) and a **duplicate search** (two `search()`
calls before the first returns → one request, two windows).

### Diagnose

```bash
lua-language-server --check=lua/jisho
```

### Benchmark (performance changes only)

```bash
vim-startuptime -vimpath nvim -count 10 -warmup 3 -- \
  -u NONE --cmd 'set rtp^=.' -c "lua require('jisho').setup()" -c qall
```

No startup regression allowed.

---

## 5. Common tasks

**Add a layout** — `style.lua`: add a function to `M.layouts`. Unknown names
fall back to `spacious`. Add it to the `layout` field of `JishoConfig`
(`init.lua`), `README.md`, and `doc/jisho.txt`.

**Change the result display** — `core/response.lua` `build_lines()`. `j`/`k`
navigation targets lines matching `^## ` and `^- **N.**` (`setup_nav()` in
`ui.lua`); keep those shapes or update the patterns.

**Add a window keymap** — `ui.lua` `open_window()`: add it to **both** the
snacks path and the native path.

**Add a `setup()` option** — default in `M.config` and a `---@field` on
`JishoConfig` in `init.lua`; document it in the README setup example and the
`*jisho-setup*` section of `doc/jisho.txt`.

**Edit the help file** — after adding or renaming a `*tag*` in
`doc/jisho.txt`, regenerate `doc/tags` and commit it with the doc:

```bash
nvim --headless -c 'helptags doc' -c q
```

---

## 6. Committing

Commit only when asked. Stage specific files, never `git add -A` /
`git add .`: the tree may hold unrelated user work. Conventional subjects:
`feat(core): …`, `fix(ui): …`, `docs: …`.
