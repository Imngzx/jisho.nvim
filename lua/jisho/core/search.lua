local M = {}

local c = require('jisho.core.cache')
local r = require('jisho.core.response')

local pcall = pcall
local vsched = vim.schedule
local vjson_dec = vim.json.decode
local vnet_req = vim.net and vim.net.request
local vsys = vim.system
local otime = os.time
local math_min = math.min
local sgsub = string.gsub
local strim = vim.trim
local vexpand = vim.fn.expand
local vnotif = vim.notify
local vlog = vim.log.levels
local tostring = tostring

local vasync_await
local vasync_run

local function ensure_async()
  if not vasync_await then
    vasync_await = vim.async.await
    vasync_run = vim.async.run
  end
end

local function call_cbs(cbs, lines, title, w, err)
  for i = 1, #cbs do
    local cb = cbs[i]
    if lines then
      vsched(function() cb(lines, title, w) end)
    else
      vsched(function() cb(nil, err) end)
    end
  end
end

local function request(w)
  local url = 'https://jisho.org/api/v1/search/words'
  if vnet_req then
    return vasync_await(function(done)
      vnet_req(url .. '?keyword=' .. c.urlencode(w), { retry = 3, verbose = false }, function(err, res)
        vsched(function() done(err, res and res.body) end)
      end)
    end)
  end
  return vasync_await(function(done)
    vsys({ 'curl', '-s', '-G', '--data-urlencode', 'keyword=' .. w, url }, { text = true }, function(obj)
      vsched(function()
        if obj.code ~= 0 or not obj.stdout then
          done('cURL Code: ' .. tostring(obj.code), nil)
        else
          done(nil, obj.stdout)
        end
      end)
    end)
  end)
end

local function proc_resp(w, cfg, cbs, spin_id, err, js)
  if err or not js then
    call_cbs(cbs, nil, nil, w, err or 'Empty response')
    c.stop_spin(false, w, err, spin_id)
    return
  end
  local ok, p = pcall(vjson_dec, js)
  if not ok or not p or not p.data or #p.data == 0 then
    call_cbs(cbs, nil, nil, w, 'Word not found')
    c.stop_spin(false, w, 'Word not found', spin_id)
    return
  end
  local lines = {}
  local li = 1
  local data = p.data
  local len = math_min(5, #data)
  for i = 1, len do
    local il = r.build_lines(data[i], cfg)
    for j = 1, #il do
      lines[li] = il[j]
      li = li + 1
    end
    r.spacer(lines, cfg.layout)
    li = #lines + 1
    lines[li] = '---'
    li = li + 1
    r.spacer(lines, cfg.layout)
    li = #lines + 1
  end
  local title = ' 辞書 Jisho.org: ' .. w .. ' '
  local ts = otime()
  c.search_cache[w] = { lines = lines, title = title, timestamp = ts, word = w }
  c.add_hist(w, ts)
  c.save_cache()
  call_cbs(cbs, lines, title, w)
  c.stop_spin(true, w, nil, spin_id)
end

function M.search(w, cfg)
  if not w or w == '' then
    w = vexpand('<cword>')
  end
  w = sgsub(strim(w), '%s+', ' ')
  if not w or w == '' then
    vnotif('Please provide the Japanese word to query.', vlog.WARN)
    return
  end
  local cached = c.search_cache[w]
  local now = otime()
  if cached and (now - cached.timestamp) < c.CACHE_TTL then
    vsched(function()
      vnotif('✓ Query successful (cached): ' .. w, vlog.INFO,
        { title = 'Jisho.org', id = 'jisho_req', timeout = 10 })
      require('jisho.ui').open_window(cached.lines, cached.title, cfg)
    end)
    c.add_hist(w, now)
    return
  end
  ensure_async()
  local cb = function(l, t) if l then require('jisho.ui').open_window(l, t, cfg) end end
  local entry = c.in_flight[w]
  if entry then
    entry.callbacks[#entry.callbacks + 1] = cb
    return
  end
  entry = { callbacks = { cb } }
  c.in_flight[w] = entry
  local spin_id = c.start_spin(w)
  entry.task = vasync_run(function()
    local ok, err, js = pcall(request, w)
    if c.in_flight[w] == entry then
      c.in_flight[w] = nil
    end
    if not ok then
      proc_resp(w, cfg, entry.callbacks, spin_id, err, nil)
      return
    end
    proc_resp(w, cfg, entry.callbacks, spin_id, err, js)
  end)
  entry.task:on_complete(function(err)
    if not err then return end
    if c.in_flight[w] == entry then
      c.in_flight[w] = nil
    end
    c.stop_spin(false, w, err, spin_id)
  end)
end

return M
