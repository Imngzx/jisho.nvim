local M = {}

M.layouts = {
  spacious = function(lines)
    lines[#lines + 1] = ''
  end,

  compact = function()
  end,

  super_spacious = function(lines)
    local n = #lines
    lines[n + 1] = ''
    lines[n + 2] = ''
  end
}

function M.spacer(lines, layout_name)
  local layout_fn = M.layouts[layout_name]
  if layout_fn then
    layout_fn(lines)
  else
    M.layouts.spacious(lines)
  end
end

return M
