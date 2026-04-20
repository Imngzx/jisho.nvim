local M = {}

M.layouts = {
  spacious = function(lines)
    table.insert(lines, '')
  end,

  compact = function(lines)
  end,

  super_spacious = function(lines)
    table.insert(lines, '')
    table.insert(lines, '')
  end
}

function M.spacer(lines, layout_name)
  local layout_fn = M.layouts[layout_name]
  if layout_fn then
    layout_fn(lines)
  else
    M.layouts["spacious"](lines)
  end
end

return M
