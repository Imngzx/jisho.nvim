-- User commands, defined at startup without loading the plugin: each one
-- requires `jisho` only when it runs.
if vim.g.loaded_jisho then return end
vim.g.loaded_jisho = true

local cmd = vim.api.nvim_create_user_command

cmd('Jisho', function(opts) require('jisho')._cmd_jisho(opts) end,
  { nargs = '*', range = true, desc = 'Jisho: look up a word, the selection, or the word under the cursor' })

cmd('JishoHistory', function() require('jisho').history() end, { desc = 'Jisho: search history' })

cmd('JishoRefresh', function(opts) require('jisho').refresh(opts.args) end,
  { nargs = '?', desc = 'Jisho: look up again, bypassing the cache' })

cmd('JishoDedupe', function(opts) require('jisho')._cmd_dedupe(opts) end, {
  nargs = '*',
  desc = 'Jisho: inspect in-flight requests, clear the cache',
  complete = function(lead)
    local out = {}
    for _, s in ipairs({ 'inflight', 'clear-inflight', 'clear-cache', 'refresh' }) do
      if vim.startswith(s, lead) then out[#out + 1] = s end
    end
    return out
  end,
})
