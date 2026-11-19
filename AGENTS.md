# jisho.nvim — AI Development Guidelines

> **Purpose:** the hard rules for editing this codebase. Read it, then read
> the source — the source wins.
> **Target:** Neovim **0.13+** (`vim.async`, `vim.net.request`).
> repo url [jisho.nvim](https://github.com/Imngzx/jisho.nvim).

---

## 1. Project structure

| Path | Role |
|---|---|
| `plugin/jisho.lua` | The `:Jisho*` user commands, defined at startup; each requires `jisho` only when run |
| `lua/jisho/init.lua` | Public API: `setup()` (optional), `search()`, `refresh()`, `history()`, command handlers |
| `lua/jisho/core/init.lua` | Re-exports `setup`, `search`, `history`, `build_lines` |
| `lua/jisho/core/cache.lua` | All shared state: result cache, history, in-flight table, progress message, URL encoding, disk persistence |
| `lua/jisho/core/search.lua` | Search flow: normalize word, cache hit, dedupe, async HTTP, process response |
| `lua/jisho/core/response.lua` | `build_lines(item, cfg)`: one Jisho API entry → Markdown lines |
| `lua/jisho/core/history.lua` | `:JishoHistory` (snacks.picker, native float fallback) |
| `lua/jisho/core/dedupe.lua` | `:JishoDedupe` / `:JishoRefresh` handlers, kana-normalized key lookup |
| `lua/jisho/ui.lua` | Result window (snacks.win or native float), `j`/`k` navigation, Budoux `w`/`b` |
| `lua/jisho/style.lua` | Layout spacers: `compact`, `spacious`, `super_spacious` |
| `test/` | Offline specs, `run.sh` runner, `helpers.lua` stubs |

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
   mangles their error-first results. Adapt explicitly and keep the handle
   in a local for the timeout (see `request()` in `core/search.lua`); the
   first outcome wins, a killed request's late callback is ignored.
3. **Cache lookup and `in_flight[word]` dedupe happen before `vim.async.run`.**
   An entry is `{ callbacks, task }`; completion clears it only if
   `in_flight[word]` is still that same entry. Every request has a timeout,
   so an entry can never stay forever.
4. **Never animate through the built-in `vim.notify`.** It ignores `id`, so
   every spinner frame becomes a `:messages` line. `use_notify()` decides:
   spinner notification (id `jisho_req`) only when a notifier plugin
   replaced `vim.notify`, else one progress message (`nvim_echo`,
   `kind = 'progress'`, id `jisho.search`). Look `vim.notify` up at call
   time; never localize it in the status code. Always close the status, and
   only from the search holding the current epoch.
5. **Keep both transports.** Native `vim.net.request` (retry = 3) and the
   `curl` fallback stay until the supported Neovim range changes.
6. **Shared state lives in `core/cache.lua`.** Other modules read it through
   the module table (`c.search_cache`, `c.in_flight`, `c.hist`); `cache.lua`
   itself uses upvalues, so reassigning a field from outside (`c.x = {}`)
   desyncs the two. Clear tables in place instead.
7. **Startup stays at `plugin/jisho.lua`.** It only defines commands; it
   must not require `jisho`. `setup()` is optional: every public entry point
   calls `ensure_setup()`, and `cache.setup()` reads the disk cache once.

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

### Test

```bash
test/run.sh                        # every spec, offline
test/run.sh test/search_spec.lua   # one or more specs
```

Each spec runs in its own `nvim -u NONE` with the working tree on the
runtimepath, `plugin/jisho.lua` sourced (`-u NONE` skips plugin files) and a throwaway `XDG_CACHE_HOME`, so the real
`~/.cache/nvim/jisho_cache.json` is never touched. `test/helpers.lua` stubs
the network: `h.stub_net()` replaces `vim.net.request`, `h.stub_curl()`
hides it and fakes `vim.system`. The helpers also replace `vim.notify`
with a recorder (`h.notes`), which auto mode takes for a notifier plugin:
specs that check the progress message pass `notify = false`. Install stubs **before** requiring
`jisho` (the modules copy these functions into locals at load). Hide
`vim.net` with `false`, never `nil`: the `vim` metatable reloads a nil
`vim.net` on the next access.

| Spec | Covers |
|---|---|
| `search_spec` | rendering, cache hit, in-flight dedupe, disk persistence, history |
| `errors_spec` | transport error, no results, retry after failure |
| `curl_spec` | `curl` fallback, `--max-time`, kill on timeout |
| `dedupe_spec` | kana-normalized key, `clear-cache`, `:JishoRefresh` |
| `budoux_spec` | `w`/`b`/`e`/`ge`: phrase stops, parity with built-in motions on non-Japanese text, counts, operator/visual, cache freed (skips without budoux.lua) |
| `progress_spec` | progress message: no `:messages` spam, final status, older search can't close a newer one |
| `notify_spec` | auto-detection, spinner frames + final notification with a notifier, `notify = false` |
| `timeout_spec` | hung request killed, entry cleared, word searchable again |
| `visual_spec` | one `{ 'n', 'x' }` mapping, `:'<,'>Jisho`, `:{range}Jisho` |
| `plugin_spec` | commands before `require`, everything works without `setup()` |
| `docs_spec` | help links resolve, `doc/tags` is current |

**Mutation-check new regression tests:** revert the fix, confirm the test
fails, restore the fix.

A live check against Jisho.org (network):

```bash
X=$(mktemp -d); XDG_CACHE_HOME=$X nvim --headless -u NONE --cmd 'set rtp^=.' -c 'runtime plugin/jisho.lua' \
  -c "lua require('jisho').setup({use_snacks=false}); require('jisho').search('食べる'); vim.wait(15000, function() return #vim.api.nvim_list_wins() > 1 end); print(#vim.api.nvim_list_wins())" \
  -c qall; rm -rf "$X"   # prints 2 when the window opened
```

### Diagnose

Run from the repo root: `--check=lua/jisho` makes that folder the
workspace, misses `.luarc.json`, and reports `vim` as an undefined global.

```bash
lua-language-server --check=.
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
`JishoConfig` in `init.lua`; document it in the README "All options" block and
the `*jisho-setup*` section of `doc/jisho.txt`. Every option needs a working
default: users are told `setup()` is optional.

**Add a command** — `plugin/jisho.lua`, with a callback that requires
`jisho` inside it; put the logic in `init.lua` (a `_cmd_*` handler).

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
