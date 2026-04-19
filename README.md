> [!WARNING]
> this plugin in currently under development, please have patience


# 辞書 jisho.nvim 🌸

----------

A blazing fast, zero-dependency Japanese dictionary plugin for Neovim, powered by [Jisho.org](https://jisho.org). 

Good for Japanese learners, anime enthusiasts, or anyone reading Japanese documentation and source code.

![Preview Image](https://github.com/user-attachments/assets/b7b6841d-24cb-4b1d-8b0b-9232b22b1755) <!-- 记得替换成你自己的截图 -->

## ✨ Features

- **Blazing Fast & Async:** Built on Neovim 0.10+ native `vim.system()`. Never blocks your UI.
- **Zero Dependencies:** Works out of the box. No external plugins required. (* optional snacks)
- **Beautiful Markdown:** Parses dictionary data into clean, readable Markdown syntax.
- **Smart UI:** Automatically integrates with [snacks.nvim](https://github.com/folke/snacks.nvim) if installed. Falls back to a handcrafted, beautiful native Neovim floating window if not.
- **Vibe Coded:** Minimalist code, extreme performance.

## 📦 Installation

### Method 1: Native `vim.pack` (No plugin manager needed)

You can install this plugin using Neovim's built-in package manager. Just clone it into your `packpath`:

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
  cmd = "Jisho",
  keys = {
    { 'n', '<leader>tj', function() require('jisho').search() end, { desc = 'Jisho (Word under cursor)' } },
    { 'v', '<leader>tj', function()
      local start_pos = vim.fn.getpos('v')
      local end_pos = vim.fn.getpos('.')
      local lines = vim.fn.getregion(start_pos, end_pos)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', true)
      require('jisho').search(table.concat(lines, ' '))
    end, { desc = 'Jisho (Selection)' } },
  },
  opts = {} -- Calls setup() automatically
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
  
  -- Settings for the native floating window (used when snacks is not available)
  window = {
    width = 0.6,      -- 60% of screen width
    height = 0.7,     -- 70% of screen height
    border = "rounded", -- "single", "double", "rounded", "solid", "shadow"
  },
})
```

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

## 🤝 Requirements
- Neovim >= 0.10.0 (uses `vim.system`)
- `curl` available in your system's PATH.
