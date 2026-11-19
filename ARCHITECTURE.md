# Architecture

How jisho.nvim is put together. The hard rules for editing it are in
`AGENTS.md`; this file explains the shape those rules protect. The source
is the final authority.

## Layers

```text
plugin/jisho.lua ── :Jisho, :JishoHistory, :JishoRefresh, :JishoDedupe
   │ (defined at startup; each requires `jisho` only when it runs)
   ▼
init.lua (public API, M.config) ── setup() optional: first use runs it
   │ search() / refresh() / history(), _cmd_* handlers
   ▼
core/init.lua ── re-exports
   │
   ├── search.lua ── normalize → cache hit → dedupe → async HTTP → proc_resp
   │      │                                              │
   │      ▼                                              ▼
   │   response.lua (build_lines) ── style.lua (spacers) │
   │                                                     ▼
   ├── history.lua ── :JishoHistory                   ui.lua ── result window
   ├── dedupe.lua  ── :JishoDedupe, :JishoRefresh       (snacks.win | native float,
   │                                                     j/k nav, Budoux motions)
   ▼
cache.lua ── shared state: search_cache, in_flight, hist, progress message,
             urlencode, load_cache/save_cache (stdpath('cache')/jisho_cache.json)
```

- Startup cost is `plugin/jisho.lua` alone (four command definitions).
- `cache.lua` requires nothing from the plugin; everything else reads its
  state through the module table. `cache.setup()` reads the disk cache
  only once, however often `jisho.setup()` runs.
- `ui.lua` is required lazily, when a result is ready to show.
- `vim.async` functions are looked up on first use (`ensure_async()` in
  `search.lua`), not at require time.

## Flow 1: `search(word)`

0. `init.lua`: no `word` in Visual mode → the selection (`getregion()`),
   then leave Visual mode. `:Jisho` with a range does the same for `'<,'>`,
   or joins the lines of any other range.
1. Empty `word` → `<cword>`. Trim and collapse whitespace; still empty →
   warn and return.
2. **Cache hit:** `search_cache[word]` younger than `CACHE_TTL` (300 s) →
   schedule the window open, report success, bump history, return.
3. **Dedupe:** if `in_flight[word]` exists, append this caller's callback
   to it and return.
4. Otherwise create `entry = { callbacks = { cb } }`, store it, open the
   progress message (returns an epoch), and `vim.async.run` the request.
5. `request(word, timeout)` awaits one transport through an explicit adapter:
   - `vim.net.request(url .. '?keyword=' .. urlencode(word), { retry = 3 })`
   - fallback: `vim.system({ 'curl', '-s', '-G', '--max-time', ..., })`

   The callback schedules `done(err, body)` and the adapter returns nothing,
   so `vim.async` has no handle to close (closing it would kill the
   request). The adapter keeps the handle itself for the timeout: a
   `vim.defer_fn` timer kills the request (`close()` / `kill(15)`) and
   finishes with "Timed out after N s". A `fin` flag lets the first outcome
   win, so the late callback of a killed request is ignored.
6. The task clears `in_flight[word]` if it is still `entry`, then
   `proc_resp()`: decode JSON, `build_lines()` for at most 5 results with
   spacers and `---` between them, store in the cache, add to history,
   save to disk, run every queued callback (scheduled), close the progress
   message.
7. `task:on_complete(err)` covers an unexpected exception: clear the entry
   (same identity check) and close the progress message with the error.

`require('jisho').search()` is fire-and-forget; no task is exposed.

## Flow 2: search status

`use_notify()` picks the style per search: the `notify` option if set,
else "is `vim.notify` replaced?" (its source is not `vim/_core/editor`, so
a notifier plugin installed it). `vim.notify` is looked up on every call,
never localized, because notifier plugins replace it lazily.

- **Spinner** (notifier): `start_spin(word)` runs an async task that sends
  the next Braille frame with id `jisho_req` and `vim.async.sleep(80)`
  while its epoch is current; the final "✓ Query successful" / "✗ Search
  failed" reuses the id, so it replaces the spinner.
- **Progress message** (built-in notify, which ignores `id`): one
  `nvim_echo` with `kind = 'progress'`, id `jisho.search`, status `running`,
  not added to history; closed with `success`, or `failed` (added to
  history). Scheduled (callers may be in a fast event) and `pcall`ed.

Both: `start_spin` returns an epoch and only the search holding the current
epoch closes the status, so an older search finishing late cannot overwrite
a newer one; its failure, if any, is still reported separately. A cache hit
reports once (`report_cached`).

## Flow 3: the result window

`open_window(lines, title, cfg)`:

- `cfg.use_snacks` and snacks loads → `snacks.win{ text = lines, ... }`.
- Otherwise a scratch buffer in a centered `nvim_open_win` float
  (`width`/`height` are ratios of the editor size), `q`/`<Esc>` close it.
- Both paths: markdown filetype, not modifiable, `setup_budoux()`,
  `setup_nav()`, then `User JishoWindowOpened` with `data = { buf, win }`.

`setup_nav()` collects the line numbers of `## ` (entry) and `- **N.**`
(sense) lines and maps `j`/`k` to jump between them.

`setup_budoux()` (only when `use_budoux` and budoux loads) maps `w`, `b`,
`e`, `ge` in Normal, Visual and Operator-pending mode. Per line,
`line_words()` lists word starts and ends using Vim's own classes
(`charclass()`: blank, punctuation, word, emoji, hiragana, katakana, CJK), so
non-Japanese text stops exactly where the built-in motions do. Inside a run
of Japanese characters (non-ASCII punctuation like 、。「」 included) the class
changes are replaced by Budoux boundaries. Results are cached per buffer
line, reset by `nvim_buf_attach` `on_lines` and dropped `on_detach`.

`step()` mirrors Vim's line crossing: an empty line is a stop for `w`/`b`/
`ge` but not `e`, a blank-only line never is; at the buffer edge `w` still
moves to the last char and `ge` to the first. Operator-pending `e`/`ge` are
mapped as `v<Cmd>…` so they are inclusive, like Vim's.

## Persistence

`save_cache()` schedules a JSON write of `{ version, cache, history }`.
`setup()` → `load_cache()` reads it back, keeping only cache entries still
inside the TTL and the full history (newest first, max 100). A file with a
different `version` is ignored.

## Limits

- At most 5 results per search; TTL 300 s and history size 100 are fixed.
- The cache key is the trimmed word as typed. Only `:JishoRefresh` uses the
  lowercased, kana-normalized key from `dedupe.lua`.
- No offline mode; no pitch-accent data (the API has none).
