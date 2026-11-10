--- Hexadecimal helpers for the pikaid test suite.

local hex = {}

--- Encode a byte string as lowercase hexadecimal.
--
-- @tparam string bytes byte string
-- @treturn string two hexadecimal digits per byte
function hex.encode(bytes)
  return (bytes:gsub(".", function(character)
    return string.format("%02x", character:byte())
  end))
end

--- Decode lowercase hexadecimal into a byte string.
--
-- @tparam string text hexadecimal text with an even number of digits
-- @treturn string the decoded bytes
function hex.decode(text)
  assert(#text % 2 == 0, "hexadecimal text must have an even length")
  assert(text:match("^[0-9a-f]*$"), "hexadecimal text must be lowercase [0-9a-f]")
  return (text:gsub("%x%x", function(pair)
    return string.char(tonumber(pair, 16))
  end))
end

return hex
