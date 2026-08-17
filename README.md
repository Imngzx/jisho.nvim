# 辞書 jisho.nvim 🌸

----------

A blazing fast, zero-dependency Japanese dictionary plugin for Neovim, powered by [Jisho.org](https://jisho.org).

Good for Japanese learners, anime enthusiasts, or anyone reading Japanese documentation and source code.

![Preview Image](https://github.com/user-attachments/assets/42d4765c-5d40-4d85-ba91-49d50e5453f9)

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

- **Blazing Fast & Async:** Built on Neovim 0.10+ native `vim.system()` + `vim.net.request()` with automatic retries. Never blocks your UI.
- **Zero Dependencies:** Works out of the box. No external plugins required. (optional: snacks.nvim, budoux.lua)
- **Beautiful Markdown:** Parses dictionary data into clean, readable Markdown with other forms, tags, sense info, see-also, and sense tags.
- **Smart UI:** Automatically integrates with [snacks.nvim](https://github.com/folke/snacks.nvim) if installed. Falls back to a handcrafted, beautiful native Neovim floating window if not.
- **Persistent Cache:** Disk cache at `~/.cache/nvim/jisho_cache.json` survives Neovim restarts with 5-minute TTL.
- **Request Deduplication:** In-flight tracking prevents duplicate API calls for the same word.
- **Search History:** `:JishoHistory` command with timestamps, Enter to re-search (snacks.picker + native fallback).
- **Navigation:** `j`/`k` jump between senses/entries, `w`/`b` Budoux-aware Japanese word jumps.
- **Modern Neovim APIs:** Uses `vim.iter`, `vim.uv`, `vim.bo`/`vim.wo`, `vim.net.request` with retries.
- **Vibe Coded:** Minimalist code, extreme performance, examined by author.

## 📦 Installation

### Method 1: Native `vim.pack` (No plugin manager needed)

You can install this plugin using Neovim's built-in package manager, or just clone it into your `packpath`:

```lua
vim.pack.add('https://github.com/Imngzx/jisho.nvim')
```

Then, add the setup and keymaps to your `init.lua`:

```lua
require('jisho').setup()

-- Setup keymaps
vim.keymap.set('n', '<leader>tj', function() require('jisho').search() end, { desc = 'Jisho (Word under cursor)' })
vim.keymap.set('v', '<leader>tj', function()
  local start_pos = vim.fn.getpos('v')
  local end_pos = vim.fn.getpos('.')
  local lines = vim.fn.getregion(start_pos, end_pos)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', true)
  require('jisho').search(table.concat(lines, ' '))
end, { desc = 'Jisho (Selection)' })
```

### Method 2: [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "Imngzx/jisho.nvim",
  cmd = { "Jisho", "JishoHistory", "JishoDedupe", "JishoRefresh" },
  keys = {
    {
      '<leader>tj',
      function() require('jisho').search() end,
      mode = 'n',
      desc = 'Jisho (Word under cursor)',
    },
    {
      '<leader>tj',
      function()
        local start_pos = vim.fn.getpos('v')
        local end_pos = vim.fn.getpos('.')
        local lines = vim.fn.getregion(start_pos, end_pos)
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', true)
        require('jisho').search(table.concat(lines, ' '))
      end,
      mode = 'v',
      desc = 'Jisho (Selection)',
    },
  },
  opts = {},
}
```

## ⚙️ Configuration

`jisho.nvim` works perfectly without any configuration, but you can customize the UI behavior.

```lua
require('jisho').setup({
  -- Auto-detect snacks.nvim by default.
  -- Set to false to force use native Neovim floating window.
  -- Set to true to force use snacks.nvim.
  use_snacks = pcall(require, 'snacks'),

  -- Auto-detect budoux.lua by default.
  -- can set to true or false
  use_budoux = pcall(require, 'budoux'),
  
  -- Settings for the native floating window (used when snacks is not available)
  window = {
    width = 0.6,      -- 60% of screen width
    height = 0.7,     -- 70% of screen height
    border = "rounded", -- "single", "double", "rounded", "solid", "shadow"
  },

  -- compact | spacious | super_spacious
  layout = "spacious"
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

If you configured the keymaps as shown above:

- **Normal Mode:** Press `<leader>tj` to translate the word directly under your cursor.
- **Visual Mode:** Select any text and press `<leader>tj` to translate the selection.

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

- Neovim >= 0.10.0 (uses `vim.system`, `vim.net.request`)
- `curl` available in your system's PATH (fallback for older Neovim versions)
- [Budoux plugin](https://github.com/atusy/budoux.lua) *optional - for Japanese word segmentation*
- [snacks.nvim](https://github.com/folke/snacks.nvim) *recommended for best UI experience*
- [Markdown rendering plugin](https://github.com/MeanderingProgrammer/render-markdown.nvim) *recommended for best markdown rendering*

## License

This project is licensed under the MIT License.
