local M = {}

local string_format = string.format
local string_upper = string.upper
local table_concat = table.concat

local function spacer(lines, layout)
  local layouts = require('jisho.style').layouts
  local layout_fn = layouts[layout]
  if layout_fn then
    layout_fn(lines)
  else
    layouts.spacious(lines)
  end
end

local function build_lines(item, config)
  local jp_list = item.japanese or {}
  local layout = config.layout
  local senses = item.senses or {}

  local lines = {}

  local main_jp = jp_list[1] or {}
  local word_jp = main_jp.word or main_jp.reading or 'Unknown'
  local reading = ''
  if main_jp.word and main_jp.reading then
    reading = ' *( ' .. main_jp.reading .. ' )*'
  end

  local is_common = item.is_common and ' `⭐ Common`' or ''
  local jlpt = ''
  if item.jlpt and #item.jlpt > 0 then
    jlpt = ' `' .. string_upper(item.jlpt[1]) .. '`'
  end

  lines[#lines + 1] = string_format('## %s%s%s%s', word_jp, reading, is_common, jlpt)
  spacer(lines, layout)

  -- Other forms (additional japanese entries)
  if #jp_list > 1 then
    local other_forms = {}
    for i = 2, #jp_list do
      local jp = jp_list[i]
      local w = jp.word or ''
      local r = jp.reading or ''
      if w ~= '' and r ~= '' and w ~= r then
        other_forms[#other_forms + 1] = string_format('%s *( %s )*', w, r)
      elseif w ~= '' then
        other_forms[#other_forms + 1] = w
      elseif r ~= '' then
        other_forms[#other_forms + 1] = r
      end
    end
    if #other_forms > 0 then
      lines[#lines + 1] = '**Other forms:** ' .. table_concat(other_forms, ', ')
      spacer(lines, layout)
    end
  end

  -- Tags
  if item.tags and #item.tags > 0 then
    lines[#lines + 1] = '**Tags:** ' .. table_concat(item.tags, ', ')
    spacer(lines, layout)
  end

  -- Senses
  for j = 1, #senses do
    local sense = senses[j]
    local eng = table_concat(sense.english_definitions or {}, ', ')
    local pos = ''
    if sense.parts_of_speech and #sense.parts_of_speech > 0 then
      pos = '`[' .. table_concat(sense.parts_of_speech, ', ') .. ']` '
    end
    lines[#lines + 1] = string_format('- **%d.** %s%s', j, pos, eng)

    -- Info/usage notes
    if sense.info and #sense.info > 0 then
      for _, note in ipairs(sense.info) do
        lines[#lines + 1] = '  > ' .. note
      end
    end

    -- See also
    if sense.see_also and #sense.see_also > 0 then
      lines[#lines + 1] = '  **See also:** ' .. table_concat(sense.see_also, ', ')
    end

    -- Sense tags
    if sense.tags and #sense.tags > 0 then
      lines[#lines + 1] = '  **Tags:** ' .. table_concat(sense.tags, ', ')
    end

    spacer(lines, layout)
  end

  return lines
end

M.build_lines = build_lines

return M