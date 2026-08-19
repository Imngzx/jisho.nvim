local M = {}

local sfmt = string.format
local supper = string.upper
local sconcat = table.concat
local srequire = require

local function spacer(lines, layout)
  local layouts = srequire('jisho.style').layouts
  local fn = layouts[layout] or layouts.spacious
  fn(lines)
end

M.spacer = spacer

local function build_lines(item, cfg)
  local jp = item.japanese or {}
  local main = jp[1] or {}
  local wjp = main.word or main.reading or 'Unknown'
  local rdg = ''
  if main.word and main.reading then
    rdg = ' *( ' .. main.reading .. ' )*'
  end
  local ic = item.is_common and ' `⭐ Common`' or ''
  local jlpt = ''
  if item.jlpt and #item.jlpt > 0 then
    jlpt = ' `' .. supper(item.jlpt[1]) .. '`'
  end
  local lines = {}
  local li = 1
  lines[li] = sfmt('## %s%s%s%s', wjp, rdg, ic, jlpt)
  li = li + 1
  spacer(lines, cfg.layout)
  li = #lines + 1
  if #jp > 1 then
    local of = {}
    for i = 2, #jp do
      local j = jp[i]
      local w = j.word or ''
      local r = j.reading or ''
      if w ~= '' and r ~= '' and w ~= r then
        of[#of + 1] = sfmt('%s *( %s )*', w, r)
      elseif w ~= '' then
        of[#of + 1] = w
      elseif r ~= '' then
        of[#of + 1] = r
      end
    end
    if #of > 0 then
      lines[li] = '**Other forms:** ' .. sconcat(of, ', ')
      li = li + 1
      spacer(lines, cfg.layout)
      li = #lines + 1
    end
  end
  if item.tags and #item.tags > 0 then
    lines[li] = '**Tags:** ' .. sconcat(item.tags, ', ')
    li = li + 1
    spacer(lines, cfg.layout)
    li = #lines + 1
  end
  local senses = item.senses or {}
  for j = 1, #senses do
    local s = senses[j]
    local eng = sconcat(s.english_definitions or {}, ', ')
    local pos = ''
    if s.parts_of_speech and #s.parts_of_speech > 0 then
      pos = '`[' .. sconcat(s.parts_of_speech, ', ') .. ']` '
    end
    lines[li] = sfmt('- **%d.** %s%s', j, pos, eng)
    li = li + 1
    if s.info and #s.info > 0 then
      for k = 1, #s.info do
        lines[li] = '  > ' .. s.info[k]
        li = li + 1
      end
    end
    if s.see_also and #s.see_also > 0 then
      lines[li] = '  **See also:** ' .. sconcat(s.see_also, ', ')
      li = li + 1
    end
    if s.tags and #s.tags > 0 then
      lines[li] = '  **Tags:** ' .. sconcat(s.tags, ', ')
      li = li + 1
    end
    spacer(lines, cfg.layout)
    li = #lines + 1
  end
  return lines
end

M.build_lines = build_lines

return M
