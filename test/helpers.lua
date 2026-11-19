-- Shared test helpers. Each spec runs in its own `nvim -u NONE` process
-- (see test/run.sh), so stubs installed here never leak between specs.
local h = {}

local results = { pass = 0, fail = 0 }

-- Record notifications instead of printing them.
h.notes = {}
vim.notify = function(msg, level, _) h.notes[#h.notes + 1] = { msg = msg, level = level } end

h.FIXTURE = vim.json.encode({
  data = {
    {
      japanese = { { word = '食べる', reading = 'たべる' }, { word = '喰べる', reading = 'たべる' } },
      is_common = true,
      jlpt = { 'jlpt-n5' },
      tags = { 'wanikani5' },
      senses = {
        { english_definitions = { 'to eat' }, parts_of_speech = { 'Ichidan verb' }, info = { 'note' } },
        { english_definitions = { 'to live on' }, parts_of_speech = {}, see_also = { '食う' } },
      },
    },
  },
})

--- Replace vim.net.request before jisho is required (search.lua copies it
--- into a local at load). Every call is recorded in `net.calls`.
---@param opts? { delay?: integer, body?: string, err?: string }
function h.stub_net(opts)
  opts = opts or {}
  local net = { calls = {} }
  vim.net = {
    request = function(url, _, cb)
      net.calls[#net.calls + 1] = url
      vim.defer_fn(function()
        if opts.err then
          cb(opts.err, nil)
        else
          cb(nil, { body = opts.body or h.FIXTURE })
        end
      end, opts.delay or 10)
    end,
  }
  return net
end

--- Hide vim.net and fake `curl` through vim.system instead. It must be
--- `false`, not nil: the `vim` metatable reloads a nil `vim.net` on access.
---@param opts? { code?: integer, body?: string }
function h.stub_curl(opts)
  opts = opts or {}
  local sys = { calls = {} }
  vim.net = false
  vim.system = function(cmd, _, cb)
    sys.calls[#sys.calls + 1] = cmd
    vim.defer_fn(function()
      cb({ code = opts.code or 0, stdout = opts.body or h.FIXTURE, stderr = '' })
    end, 10)
    return {}
  end
  return sys
end

function h.float_count()
  local n = 0
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= '' then n = n + 1 end
  end
  return n
end

function h.close_floats()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= '' then vim.api.nvim_win_close(w, true) end
  end
end

---@param n integer
---@param ms? integer
function h.wait_floats(n, ms)
  return vim.wait(ms or 2000, function() return h.float_count() >= n end, 5)
end

function h.read_cache_file()
  local f = io.open(require('jisho.core.cache').CACHE_FILE, 'r')
  if not f then return nil end
  local s = f:read('*a')
  f:close()
  return vim.json.decode(s)
end

--- Let scheduled callbacks (save_cache, notifications) run.
function h.drain(ms)
  vim.wait(ms or 50)
end

function h.eq(want, got, what)
  if not vim.deep_equal(want, got) then
    error(('%s: want %s, got %s'):format(what or 'eq', vim.inspect(want), vim.inspect(got)), 2)
  end
end

function h.ok(v, what)
  if not v then error((what or 'expected truthy') .. ', got ' .. vim.inspect(v), 2) end
end

function h.test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  h.close_floats()
  if ok then
    results.pass = results.pass + 1
    io.stdout:write('  ok    ', name, '\n')
  else
    results.fail = results.fail + 1
    io.stdout:write('  FAIL  ', name, '\n', err, '\n')
  end
end

function h.finish()
  io.stdout:write(('  %d passed, %d failed\n'):format(results.pass, results.fail))
  vim.cmd(results.fail == 0 and 'qall!' or 'cquit! 1')
end

return h
