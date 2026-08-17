local M = {}

local c = require('jisho.core.cache')
local r = require('jisho.core.response')

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

local function proc_resp(w, cfg, cbs, err, js)
  c.in_flight[w] = nil
  if err or not js then
    for i = 1, #cbs do
      vsched(function() cbs[i](nil, err or 'Empty response') end)
    end
    c.stop_spin(false, w, err)
    return
  end
  local ok, p = pcall(vjson_dec, js)
  if not ok or not p or not p.data or #p.data == 0 then
    for i = 1, #cbs do
      vsched(function() cbs[i](nil, 'Word not found') end)
    end
    c.stop_spin(false, w, 'Word not found')
    return
  end
  local lines = {}
  local data = p.data
  local len = math_min(5, #data)
  for i = 1, len do
    local item = data[i]
    local il = r.build_lines(item, cfg)
    for j = 1, #il do
      lines[#lines + 1] = il[j]
    end
    r.spacer(lines, cfg.layout)
    lines[#lines + 1] = '---'
    r.spacer(lines, cfg.layout)
  end
  local title = ' 辞書 Jisho.org: ' .. w .. ' '
  local ts = otime()
  c.search_cache[w] = { lines = lines, title = title, timestamp = ts, word = w }
  c.add_hist(w, ts)
  c.save_cache()
  for i = 1, #cbs do
    vsched(function() cbs[i](lines, title, w) end)
  end
  c.stop_spin(true, w)
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
      vnotif('✓ Query successful (cached): ' .. w, vlog.INFO, { title = 'Jisho.org', id = 'jisho_req', timeout = 10 })
      require('jisho.ui').open_window(cached.lines, cached.title, cfg)
    end)
    c.add_hist(w, now)
    return
  end
  local cbs = { function(l, t) if l then require('jisho.ui').open_window(l, t, cfg) end end }
  if c.in_flight[w] then
    c.in_flight[w].callbacks[#c.in_flight[w].callbacks + 1] = cbs[1]
    return
  end
  c.in_flight[w] = { callbacks = cbs }
  c.start_spin(w)
  local url = 'https://jisho.org/api/v1/search/words'
  if vnet_req then
    vnet_req(url .. '?keyword=' .. c.urlencode(w), { retry = 3, verbose = false }, function(err, res)
      proc_resp(w, cfg, c.in_flight[w] and c.in_flight[w].callbacks or cbs, err, res and res.body)
    end)
  else
    vsys({ 'curl', '-s', '-G', '--data-urlencode', 'keyword=' .. w, url }, { text = true }, function(obj)
      if obj.code ~= 0 or not obj.stdout then
        proc_resp(w, cfg, c.in_flight[w] and c.in_flight[w].callbacks or cbs, 'cURL Code: ' .. tostring(obj.code), nil)
      else
        proc_resp(w, cfg, c.in_flight[w] and c.in_flight[w].callbacks or cbs, nil, obj.stdout)
      end
    end)
  end
end

return M