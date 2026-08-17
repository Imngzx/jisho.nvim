local M = {}

local cache = require('jisho.core.cache')
local search = require('jisho.core.search')
local history = require('jisho.core.history')
local response = require('jisho.core.response')

-- Public API
M.setup = cache.setup
M.search = search.search
M.history = history.history
M.build_lines = response.build_lines

return M
