# `vim.async` in jisho.nvim (Neovim 0.13+)

> **Verified against**: Neovim v0.13.0-dev runtime source and headless native/curl request smoke tests.
> **Scope**: Structured async orchestration for `core/search.lua` and `core/cache.lua`.

---

## API Facts

| API | Use |
|---|---|
| `vim.async.run(fn)` | Runs `fn` in a task and returns its task handle. |
| `vim.async.await(fn)` | Suspends the current task until `fn(done)` calls `done(...)`. |
| `vim.async.await(argc, fn, ...)` | Inserts a callback at `argc`; callback values are returned unchanged. |
| `vim.async.pawait(...)` | Protected `await`; returns `ok, ...`. |
| `vim.async.sleep(ms)` | Cooperative timer checkpoint. |
| `task:on_complete(fn)` | Observes task success or failure. |
| `task:close()` | Cooperatively cancels an awaiting task and its owned closable work. |

`await` is valid only inside `vim.async.run` (or another async task). `vim.async` is cooperative: it does not interrupt synchronous Lua code.

---

## Callback Contract: Important

`vim.async.await(argc, fn, ...)` treats a callback-style API as **success-only**. Internally it prepends a synthetic `nil` error slot, then returns the callback's values unchanged after that slot.

Use direct positional wrapping only for APIs whose callback has no error-first result, such as `vim.uv.fs_stat`:

```lua
local err, stat = vim.async.await(2, vim.uv.fs_stat, path)
```

Do **not** directly use this form for error-first APIs such as `vim.net.request(url, opts, callback)` or the `vim.system(..., callback)` result callback. Doing so transforms their callback arguments and makes error handling ambiguous.

### Correct jisho.nvim adapter pattern

Wrap each error-first callback explicitly and **do not return its closable request/job handle**. `vim.async` closes a returned handle after normal completion as cleanup; `vim.net.request`'s `close()` kills the request. Returning no handle preserves successful completion.

```lua
local err, body = vim.async.await(function(done)
  vim.net.request(url, opts, function(request_err, response)
    vim.schedule(function()
      done(request_err, response and response.body)
    end)
  end)
end)
```

`vim.net.request` and `vim.system` callbacks can arrive from a fast event. Schedule `done(...)`, notifications, and UI work before invoking them.

---

## Current Plugin Design

### `core/search.lua`

1. Performs word normalization, cache hit, and in-flight lookup synchronously.
2. Stores `{ callbacks, task }` in `cache.in_flight[word]` before starting work.
3. Uses `vim.async.run` to await one of two adapters:
   - Native `vim.net.request` with retries.
   - `vim.system` curl fallback.
4. Clears the in-flight entry only if it is still the task's own entry.
5. Builds lines, persists cache/history, calls all deduplicated callbacks, and stops its own spinner.
6. Observes task failure so an unexpected async exception still clears in-flight state and stops the spinner.

Public `require('jisho').search(word)` remains fire-and-forget. It does not expose a task; this avoids an API change.

### `core/cache.lua` spinner

`start_spin(word)` creates a task that notifies immediately then calls `vim.async.sleep(80)` while its epoch remains current. It returns that epoch. `stop_spin(..., epoch)` advances the epoch only for the matching search. An older search therefore cannot stop or overwrite a newer spinner.

No `uv.new_timer`, timer stop, or timer close lifecycle remains.

---

## Required Localizations

```lua
local vasync_await = vim.async.await
local vasync_run = vim.async.run
local vasync_sleep = vim.async.sleep
local vsched = vim.schedule
```

Maintain repository conventions: numeric loops, explicit callback locals before scheduled closures, manual indexes for tight line-building loops, and all `vim.*` symbols localized at module top.

---

## Rules for Future Changes

1. Keep cache checks and in-flight deduplication outside the task.
2. Keep one `in_flight[word]` entry per request; late completion must not delete a replacement entry.
3. Schedule Neovim UI APIs and `vim.notify` from callback/fast-event paths.
4. Keep callback invocation scheduled; search consumers currently expect UI opening through that path.
5. Use `vim.async.pawait` only if a recoverable awaited failure must continue within the same task.
6. Preserve the curl fallback unless the supported Neovim range explicitly changes to 0.13+.
7. Re-run native, curl, cache-hit, and duplicate-search headless smoke scenarios after async changes.
