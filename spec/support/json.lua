--- Minimal JSON decoder used only by the pikaid test suite.
--
-- It supports the subset used by the pikaid conformance fixture and the
-- generated reference cases: objects, arrays, strings (including escapes),
-- integers, booleans, and null. It is not part of the installed library.

local json = {}

local escapes = {
  ['"'] = '"',
  ["\\"] = "\\",
  ["/"] = "/",
  b = "\b",
  f = "\f",
  n = "\n",
  r = "\r",
  t = "\t",
}

local function skip_whitespace(text, position)
  local first = text:find("[^ \t\r\n]", position)
  return first or (#text + 1)
end

local function parse_string(text, position)
  local parts = {}
  local index = position + 1

  while true do
    local special = text:find('["\\]', index)

    if not special then
      error(string.format("unterminated string at byte %d", position))
    end

    parts[#parts + 1] = text:sub(index, special - 1)

    if text:sub(special, special) == '"' then
      return table.concat(parts), special + 1
    end

    local escape = text:sub(special + 1, special + 1)

    if escape == "u" then
      local hex = text:sub(special + 2, special + 5)
      if not hex:match("^%x%x%x%x$") then
        error(string.format("invalid unicode escape at byte %d", special))
      end
      local codepoint = tonumber(hex, 16)
      if codepoint >= 0xD800 and codepoint <= 0xDFFF then
        error("surrogate code points are not supported")
      end
      parts[#parts + 1] = utf8.char(codepoint)
      index = special + 6
    else
      local replacement = escapes[escape]
      if not replacement then
        error(string.format("invalid escape at byte %d", special))
      end
      parts[#parts + 1] = replacement
      index = special + 2
    end
  end
end

local function parse_number(text, position)
  local literal = text:match("^-?%d+", position)

  if not literal then
    error(string.format("invalid number at byte %d", position))
  end

  return tonumber(literal), position + #literal
end

local parse_value

local function parse_array(text, position)
  local values = {}
  position = skip_whitespace(text, position + 1)

  if text:sub(position, position) == "]" then
    return values, position + 1
  end

  while true do
    local value
    value, position = parse_value(text, position)
    values[#values + 1] = value
    position = skip_whitespace(text, position)

    local delimiter = text:sub(position, position)

    if delimiter == "]" then
      return values, position + 1
    end

    if delimiter ~= "," then
      error(string.format("expected ',' or ']' at byte %d", position))
    end

    position = skip_whitespace(text, position + 1)
  end
end

local function parse_object(text, position)
  local values = {}
  position = skip_whitespace(text, position + 1)

  if text:sub(position, position) == "}" then
    return values, position + 1
  end

  while true do
    if text:sub(position, position) ~= '"' then
      error(string.format("expected object key at byte %d", position))
    end

    local key
    key, position = parse_string(text, position)
    position = skip_whitespace(text, position)

    if text:sub(position, position) ~= ":" then
      error(string.format("expected ':' at byte %d", position))
    end

    local value
    value, position = parse_value(text, skip_whitespace(text, position + 1))
    values[key] = value
    position = skip_whitespace(text, position)

    local delimiter = text:sub(position, position)

    if delimiter == "}" then
      return values, position + 1
    end

    if delimiter ~= "," then
      error(string.format("expected ',' or '}' at byte %d", position))
    end

    position = skip_whitespace(text, position + 1)
  end
end

parse_value = function(text, position)
  position = skip_whitespace(text, position)
  local character = text:sub(position, position)

  if character == "{" then
    return parse_object(text, position)
  elseif character == "[" then
    return parse_array(text, position)
  elseif character == '"' then
    return parse_string(text, position)
  elseif character == "-" or character:match("%d") then
    return parse_number(text, position)
  elseif text:sub(position, position + 3) == "true" then
    return true, position + 4
  elseif text:sub(position, position + 4) == "false" then
    return false, position + 5
  elseif text:sub(position, position + 3) == "null" then
    return nil, position + 4
  end

  error(string.format("unexpected character at byte %d", position))
end

--- Decode a JSON document.
--
-- @tparam string text JSON source
-- @return the decoded value
function json.decode(text)
  local value, position = parse_value(text, 1)
  position = skip_whitespace(text, position)

  if position <= #text then
    error(string.format("trailing data at byte %d", position))
  end

  return value
end

return json
