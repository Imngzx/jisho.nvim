# Architecture

How jisho.nvim is put together. The hard rules for editing it are in
`AGENTS.md`; this file explains the shape those rules protect. The source
is the final authority.

## Layers

```text
init.lua (public API, :Jisho* commands, M.config)
   │ setup() / search() / history()
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
   │                                                     j/k nav, Budoux w/b)
   ▼
cache.lua ── shared state: search_cache, in_flight, hist, spinner,
             urlencode, load_cache/save_cache (stdpath('cache')/jisho_cache.json)
```

- `cache.lua` requires nothing from the plugin; everything else reads its
  state through the module table.
- `ui.lua` is required lazily, when a result is ready to show.
- `vim.async` functions are looked up on first use (`ensure_async()` in
  `search.lua` and `cache.lua`), not at require time.

## Flow 1: `search(word)`

1. Empty `word` → `<cword>`. Trim and collapse whitespace; still empty →
   warn and return.
2. **Cache hit:** `search_cache[word]` younger than `CACHE_TTL` (300 s) →
   schedule the window open, bump history, return. No request.
3. **Dedupe:** if `in_flight[word]` exists, append this caller's callback
   to it and return.
4. Otherwise create `entry = { callbacks = { cb } }`, store it, start the
   spinner (returns an epoch), and `vim.async.run` the request.
5. `request(word)` awaits one transport through an explicit adapter:
   - `vim.net.request(url .. '?keyword=' .. urlencode(word), { retry = 3 })`
   - fallback: `vim.system({ 'curl', '-s', '-G', '--data-urlencode', ... })`

   The callback schedules `done(err, body)` and the adapter returns nothing,
   so `vim.async` has no handle to close (closing it would kill the request).
6. The task clears `in_flight[word]` if it is still `entry`, then
   `proc_resp()`: decode JSON, `build_lines()` for at most 5 results with
   spacers and `---` between them, store in the cache, add to history,
   save to disk, run every queued callback (scheduled), stop the spinner.
7. `task:on_complete(err)` covers an unexpected exception: clear the entry
   (same identity check) and stop the spinner with the error.

`require('jisho').search()` is fire-and-forget; no task is exposed.

## Flow 2: the spinner

`start_spin(word)` bumps `spin_epoch` and runs a task that calls
`vim.notify` with the next Braille frame (same notification `id`, so it
replaces itself) and `vim.async.sleep(80)` while its epoch is current.
`stop_spin(ok, word, err, epoch)` bumps the epoch only if it matches, then
schedules the success/failure notification. An older search can therefore
never stop a newer search's spinner.

## Flow 3: the result window

`open_window(lines, title, cfg)`:

- `cfg.use_snacks` and snacks loads → `snacks.win{ text = lines, ... }`.
- Otherwise a scratch buffer in a centered `nvim_open_win` float
  (`width`/`height` are ratios of the editor size), `q`/`<Esc>` close it.
- Both paths: markdown filetype, not modifiable, `setup_budoux()`,
  `setup_nav()`, then `User JishoWindowOpened` with `data = { buf, win }`.

`setup_nav()` collects the line numbers of `## ` (entry) and `- **N.**`
(sense) lines and maps `j`/`k` to jump between them. `setup_budoux()` (only
when `use_budoux` and budoux loads) parses a line's segment boundaries once
per buffer line, invalidated by `nvim_buf_attach` `on_lines`; lines with no
non-ASCII byte fall back to `normal! w` / `normal! b`.

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
