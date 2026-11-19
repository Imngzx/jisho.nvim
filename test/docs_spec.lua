-- doc/jisho.txt: every |link| resolves and doc/tags is up to date.
local h = dofile('test/helpers.lua')

h.test('help links resolve', function()
  local bad = {}
  for _, l in ipairs(vim.fn.readfile('doc/jisho.txt')) do
    for t in l:gmatch('|([^|%s]+)|') do
      if #vim.fn.getcompletion(t, 'help') == 0 then bad[#bad + 1] = t end
    end
  end
  h.eq({}, bad, 'broken links')
end)

h.test('doc/tags matches :helptags output', function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, 'p')
  vim.fn.writefile(vim.fn.readfile('doc/jisho.txt'), tmp .. '/jisho.txt')
  vim.cmd.helptags(vim.fn.fnameescape(tmp))
  h.eq(vim.fn.readfile(tmp .. '/tags'), vim.fn.readfile('doc/tags'), 'doc/tags (run: nvim --headless -c "helptags doc" -c q)')
end)

h.finish()
