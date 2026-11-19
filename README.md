# 辞書 jisho.nvim 🌸

----------

A blazing fast, zero-dependency Japanese dictionary plugin for Neovim, powered by [Jisho.org](https://jisho.org).

Good for Japanese learners, anime enthusiasts, or anyone reading Japanese documentation and source code.

> [!WARNING]
> This plugin requires latest 0.13 nightly

![Preview Image](https://github.com/user-attachments/assets/b5414cfb-b212-40b6-8171-2e96f467a75f)

## Layout Previews

<details>
    <summary> Compact Layout </summary>
    <img src = "https://github.com/user-attachments/assets/07ba2319-a2e5-40a3-b5f9-377a0df84266">
</details>
<details>
    <summary> Spacious Layout </summary>
    <img src = "https://github.com/user-attachments/assets/e88c8697-03bf-4387-b4e7-0985bee07972">
</details>
<details>
    <summary> Super Spacious Layout </summary>
    <img src = "https://github.com/user-attachments/assets/58e590ed-6efb-4416-ac0a-f6bddbde9b0e">
</details>

## ✨ Features

- **Async:** Built on Neovim 0.13+ `vim.async` and `vim.net.request` (with retries), `curl` as fallback. Never blocks your UI.
- **Zero Dependencies:** Works out of the box. Optional: [snacks.nvim](https://github.com/folke/snacks.nvim), [budoux.lua](https://github.com/atusy/budoux.lua).
- **Markdown Results:** Reading, common/JLPT tags, other forms, tags, numbered senses with usage notes and see-also.
- **Smart UI:** Uses snacks.nvim if installed, otherwise a native floating window.
- **Persistent Cache:** Results are kept for 5 minutes, also across restarts (`stdpath('cache')/jisho_cache.json`).
- **Request Deduplication:** Searching a word that is already being fetched does not send a second request.
- **Search History:** `:JishoHistory`, `<CR>` to search again.
- **Navigation:** `j`/`k` jump between entries and senses, `w`/`b` Budoux-aware Japanese word jumps.
- **Vibe Coded:** Minimalist code, extreme performance, examined by author.

## 📦 Installation

Every method below uses the same two keymaps:

```lua
-- Normal mode: word under the cursor
local function jisho_cword() require('jisho').search() end

-- Visual mode: the selection
local function jisho_visual()
  local text = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = vim.fn.mode() })
  vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'n', false)
  require('jisho').search(table.concat(text, ' '))
end
```

### Method 1: Native `vim.pack`

```lua
vim.pack.add({ 'https://github.com/Imngzx/jisho.nvim' })
require('jisho').setup()

vim.keymap.set('n', '<leader>tj', jisho_cword, { desc = 'Jisho (Word under cursor)' })
vim.keymap.set('x', '<leader>tj', jisho_visual, { desc = 'Jisho (Selection)' })
```

### Method 2: [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'Imngzx/jisho.nvim',
  cmd = { 'Jisho', 'JishoHistory', 'JishoDedupe', 'JishoRefresh' },
  keys = {
    { '<leader>tj', jisho_cword, mode = 'n', desc = 'Jisho (Word under cursor)' },
    { '<leader>tj', jisho_visual, mode = 'x', desc = 'Jisho (Selection)' },
  },
  opts = {},
}
```

### Method 3: [Resonance.nvim](https://github.com/Imngzx/resonance.nvim)

```lua
require('resonance').load({
  'https://github.com/Imngzx/jisho.nvim',
  dependencies = { 'https://github.com/atusy/budoux.lua' }, -- optional
  cmd = { 'Jisho', 'JishoHistory', 'JishoDedupe', 'JishoRefresh' },
  keys = {
    { 'n', '<leader>tj', jisho_cword, { desc = 'Jisho (Word under cursor)' } },
    { 'x', '<leader>tj', jisho_visual, { desc = 'Jisho (Selection)' } },
  },
  config = function()
    require('jisho').setup({ use_budoux = true, layout = 'spacious' })
  end,
})
```

## ⚙️ Configuration

`setup()` is optional. Defaults:

```lua
require('jisho').setup({
  use_snacks = pcall(require, 'snacks'), -- false: native floating window
  use_budoux = pcall(require, 'budoux'), -- Budoux-aware w/b
  layout = 'spacious',                   -- compact | spacious | super_spacious
  window = {
    width = 0.6,        -- ratio of the editor width
    height = 0.7,       -- ratio of the editor height
    border = 'rounded', -- single | double | rounded | solid | shadow | none
  },
})
```

> [!TIP]
> You can add it into which-key

Here's my [jisho](https://github.com/Imngzx/nvim-config-rice-.ver-/blob/nvim-native/lua/plugins/jisho.lua) + [my budoux and which-key](https://github.com/Imngzx/nvim-config-rice-.ver-/blob/nvim-native/lua/plugins/jisho.lua) configuration file for Neovim

## 🚀 Usage

### Command Line

You can search any word anywhere via the command line:

```vim
:Jisho 食べる
:Jisho hello
```

### Keymaps

With the keymaps above, `<leader>tj` looks up the word under the cursor (normal mode) or the selection (visual mode).

### User Commands

| Command | Description |
|---------|-------------|
| `:Jisho [word]` | Search for a word (uses word under cursor if omitted) |
| `:JishoHistory` | Open search history picker (snacks.picker or native) |
| `:JishoDedupe inflight` | Inspect in-flight requests |
| `:JishoDedupe clear-inflight` | Clear all in-flight requests |
| `:JishoDedupe clear-cache` | Clear search cache |
| `:JishoDedupe refresh [word]` | Force refresh (bypasses cache) |
| `:JishoRefresh [word]` | Shortcut for force refresh |

### Result Window Navigation

| Key | Action |
|-----|--------|
| `j` / `k` | Jump between senses/entries |
| `w` / `b` | Budoux-aware Japanese word jumps |
| `q` / `<Esc>` | Close window |
| `<CR>` (in history) | Re-search selected entry |

## 🤝 Requirements

- Neovim >= 0.13 (`vim.async`, `vim.net.request`)
- `curl` in PATH, only if `vim.net.request` is unavailable
- Optional: [budoux.lua](https://github.com/atusy/budoux.lua) (word segmentation), [snacks.nvim](https://github.com/folke/snacks.nvim) (UI), [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) (rendering)

Full reference: `:help jisho`.

## License

This project is licensed under the MIT License.
