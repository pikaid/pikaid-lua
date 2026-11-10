--- Base36 primitives for the pikaid wire format.
--
-- This module is an implementation detail of `pikaid`. It encodes the two
-- fixed-width fields defined by pikaid specification revision 1.0.4:
--
--  * a timestamp of at most 36^7 - 1 (7 Base36 digits), and
--  * randomness of at most 2^96 - 1 (19 Base36 digits, 12 bytes).
--
-- The 96-bit field never fits in a Lua integer on most platforms, so it is
-- processed as six 16-bit limbs. Every intermediate value stays below 2^37,
-- which is exact in a Lua integer and in an IEEE 754 double.
--
-- @module pikaid.base36

local base36 = {}

--- The canonical pikaid alphabet, in ascending digit order.
base36.ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"

--- Largest representable timestamp, 36^7 - 1.
base36.MAX_TIMESTAMP = 78364164095

-- A 32-bit integer build cannot represent MAX_TIMESTAMP and would silently
-- corrupt the fixed-width arithmetic below. Refuse to load instead of
-- producing identifiers that are merely plausible.
if math.maxinteger < base36.MAX_TIMESTAMP then
  error(
    "pikaid requires a Lua build with 64-bit integers; this interpreter has "
      .. "32-bit integers (for example LUA_32BITS), which the pikaid 1.0.4 "
      .. "format cannot represent exactly",
    0
  )
end

local ALPHABET = base36.ALPHABET
local DIGIT_VALUES = {}

for value = 0, 35 do
  DIGIT_VALUES[ALPHABET:byte(value + 1)] = value
end

local ENTROPY_LIMBS = 6
local ENTROPY_BYTES = 12
local LIMB_BASE = 65536

--- Encode a non-negative integer as fixed-width lowercase Base36.
--
-- @tparam integer value value to encode
-- @tparam integer width exact number of digits
-- @treturn string the encoded value, left-padded with `0`
function base36.encode(value, width)
  local digits = {}

  for position = width, 1, -1 do
    local digit = value % 36
    digits[position] = ALPHABET:sub(digit + 1, digit + 1)
    value = value // 36
  end

  assert(value == 0, "value does not fit in the requested width")

  return table.concat(digits)
end

--- Decode `count` Base36 digits starting at byte `first`.
--
-- @tparam string text source string
-- @tparam integer first one-based byte offset of the first digit
-- @tparam integer count number of digits to decode
-- @treturn integer|nil the decoded value, or `nil` for a non-Base36 byte
function base36.decode(text, first, count)
  local value = 0

  for position = first, first + count - 1 do
    local digit = DIGIT_VALUES[text:byte(position)]
    if digit == nil then
      return nil
    end
    value = value * 36 + digit
  end

  return value
end

--- Encode exactly 12 randomness bytes as 19 lowercase Base36 digits.
--
-- The bytes are interpreted as an unsigned 96-bit big-endian integer. The
-- leading zero digits are always emitted.
--
-- @tparam string bytes exactly 12 bytes
-- @treturn string exactly 19 Base36 digits
function base36.encode_randomness(bytes)
  assert(#bytes == ENTROPY_BYTES, "randomness must be exactly 12 bytes")

  local limbs = {}

  for index = 1, ENTROPY_LIMBS do
    local high = bytes:byte(index * 2 - 1)
    local low = bytes:byte(index * 2)
    limbs[index] = high * 256 + low
  end

  local digits = {}

  -- Long division by 36, most significant limb first. The remainder of each
  -- step is at most 35, so every quotient limb stays within 16 bits.
  for position = 19, 1, -1 do
    local remainder = 0

    for index = 1, ENTROPY_LIMBS do
      local value = limbs[index] + remainder * LIMB_BASE
      limbs[index] = value // 36
      remainder = value % 36
    end

    digits[position] = ALPHABET:sub(remainder + 1, remainder + 1)
  end

  return table.concat(digits)
end

--- Decode 19 Base36 digits starting at byte `first` into 12 bytes.
--
-- Values above 2^96 - 1 are rejected instead of being truncated.
--
-- @tparam string text source string
-- @tparam integer first one-based byte offset of the first digit
-- @treturn string|nil exactly 12 bytes, or `nil`
-- @treturn string|nil `"invalid_character"` or `"overflow"` when decoding fails
function base36.decode_randomness(text, first)
  local limbs = { 0, 0, 0, 0, 0, 0 }

  for position = first, first + 18 do
    local digit = DIGIT_VALUES[text:byte(position)]
    if digit == nil then
      return nil, "invalid_character"
    end

    local carry = digit

    -- Multiply the 96-bit accumulator by 36 and add the new digit, least
    -- significant limb first. A carry out of the most significant limb means
    -- the accumulated value no longer fits in 96 bits.
    for index = ENTROPY_LIMBS, 1, -1 do
      local value = limbs[index] * 36 + carry
      limbs[index] = value % LIMB_BASE
      carry = value // LIMB_BASE
    end

    if carry ~= 0 then
      return nil, "overflow"
    end
  end

  local bytes = {}

  for index = 1, ENTROPY_LIMBS do
    local limb = limbs[index]
    bytes[index * 2 - 1] = string.char(limb // 256)
    bytes[index * 2] = string.char(limb % 256)
  end

  return table.concat(bytes)
end

return base36
