--- pikaid — official Lua implementation.
--
-- pikaid is an immutable, unversioned identifier format: exactly 26 lowercase
-- Base36 characters made of a seven-digit whole-second Unix timestamp followed
-- by nineteen digits carrying 96 bits of cryptographic randomness. The
-- equivalent binary form is exactly 17 bytes: five unsigned big-endian
-- timestamp bytes followed by the twelve randomness bytes unchanged.
--
-- This module implements pikaid specification revision 1.0.4. It requires
-- Lua 5.3 or newer (integer subtype, `//`, `math.type`) and a cryptographic
-- entropy source. The built-in source reads `/dev/urandom`; on platforms
-- without it, construct an instance with a verified provider:
--
-- ```lua
-- local pikaid = require("pikaid")
-- local ids = pikaid.new({
--   entropy = function(count) return my_csprng(count) end,
--   clock = os.time,
-- })
-- local id = ids.generate()
-- ```
--
-- pikaid values are identifiers, not secrets, authentication tokens, or
-- authorization checks. Uniqueness is probabilistic, timestamps have
-- one-second precision, and generation within one second is not monotonic.
--
-- @module pikaid

local base36 = require("pikaid.base36")
local entropy = require("pikaid.entropy")

local pikaid = {}

--- Library version (the identifier format itself is unversioned).
pikaid.VERSION = "0.1.0"

--- Exact length of a pikaid string.
pikaid.STRING_LENGTH = 26

--- Exact length of a pikaid binary value.
pikaid.BINARY_LENGTH = 17

--- Number of Base36 digits in the timestamp field.
pikaid.TIMESTAMP_DIGITS = 7

--- Number of Base36 digits in the randomness field.
pikaid.RANDOMNESS_DIGITS = 19

--- Number of raw randomness bytes.
pikaid.ENTROPY_BYTES = 12

--- Largest valid timestamp, 36^7 - 1 (4453-04-05T15:21:35Z).
pikaid.MAX_TIMESTAMP = base36.MAX_TIMESTAMP

local MAX_TIMESTAMP = pikaid.MAX_TIMESTAMP
local TIMESTAMP_DIGITS = pikaid.TIMESTAMP_DIGITS
local STRING_LENGTH = pikaid.STRING_LENGTH
local BINARY_LENGTH = pikaid.BINARY_LENGTH
local ENTROPY_BYTES = pikaid.ENTROPY_BYTES
local BINARY_TIMESTAMP_BYTES = 5

local Error = {}
Error.__index = Error

Error.__tostring = function(self)
  return string.format("pikaid: %s: %s", self.code, self.message)
end

local function new_error(code, message)
  return setmetatable({ code = code, message = message }, Error)
end

local function fail(code, message)
  error(new_error(code, message), 0)
end

local function describe_value(value)
  if type(value) == "string" then
    return string.format("string of length %d", #value)
  end
  return type(value)
end

local function to_hex(bytes)
  return (bytes:gsub(".", function(character)
    return string.format("%02x", character:byte())
  end))
end

local function encode_binary_timestamp(timestamp)
  local bytes = {}

  for position = BINARY_TIMESTAMP_BYTES, 1, -1 do
    bytes[position] = string.char(timestamp % 256)
    timestamp = timestamp // 256
  end

  return table.concat(bytes)
end

local function decode_binary_timestamp(bytes)
  local timestamp = 0

  for position = 1, BINARY_TIMESTAMP_BYTES do
    timestamp = timestamp * 256 + bytes:byte(position)
  end

  return timestamp
end

local function check_timestamp(timestamp)
  if type(timestamp) ~= "number" or math.type(timestamp) ~= "integer" then
    fail(
      "invalid_timestamp",
      "timestamp must be an integer number of Unix seconds, got " .. describe_value(timestamp)
    )
  end

  if timestamp < 0 or timestamp > MAX_TIMESTAMP then
    fail(
      "timestamp_out_of_range",
      string.format("timestamp %d is outside the valid range 0..%d", timestamp, MAX_TIMESTAMP)
    )
  end

  return timestamp
end

local function draw_randomness(provider)
  local ok, bytes = pcall(provider, ENTROPY_BYTES)

  if not ok then
    fail("entropy_unavailable", "entropy provider failed: " .. tostring(bytes))
  end

  if type(bytes) ~= "string" then
    fail(
      "entropy_unavailable",
      "entropy provider must return a string, got " .. describe_value(bytes)
    )
  end

  if #bytes ~= ENTROPY_BYTES then
    fail(
      "entropy_unavailable",
      string.format(
        "entropy provider returned %d bytes, expected exactly %d",
        #bytes,
        ENTROPY_BYTES
      )
    )
  end

  return bytes
end

local function resolve_timestamp(clock, timestamp)
  if timestamp == nil then
    local ok, value = pcall(clock)

    if not ok then
      fail("clock_unavailable", "clock provider failed: " .. tostring(value))
    end

    timestamp = value
  end

  return check_timestamp(timestamp)
end

local function generate(entropy_provider, clock, timestamp)
  local seconds = resolve_timestamp(clock, timestamp)
  local randomness = draw_randomness(entropy_provider)

  return base36.encode(seconds, TIMESTAMP_DIGITS) .. base36.encode_randomness(randomness)
end

local function generate_binary(entropy_provider, clock, timestamp)
  local seconds = resolve_timestamp(clock, timestamp)
  local randomness = draw_randomness(entropy_provider)

  return encode_binary_timestamp(seconds) .. randomness
end

--- Generate a pikaid string.
--
-- The timestamp defaults to `os.time()`; passing an explicit value allows
-- deterministic tests, backfills, and fixtures. An explicit timestamp is still
-- range-checked. Exactly 12 bytes are read from the configured CSPRNG on every
-- call.
--
-- @tparam[opt] integer timestamp whole Unix seconds, `0..78364164095`
-- @treturn string a 26-character pikaid
function pikaid.generate(timestamp)
  return generate(entropy.bytes, os.time, timestamp)
end

--- Generate a pikaid in its 17-byte binary representation.
--
-- @tparam[opt] integer timestamp whole Unix seconds, `0..78364164095`
-- @treturn string a 17-byte binary pikaid
function pikaid.generate_binary(timestamp)
  return generate_binary(entropy.bytes, os.time, timestamp)
end

--- Create a generator with an explicit entropy provider and/or clock.
--
-- This is the supported way to use pikaid on platforms without
-- `/dev/urandom`, or with a runtime-provided CSPRNG (for example an OpenResty
-- or host-application RNG). The provider is trusted: pikaid only checks that
-- it returns exactly 12 bytes, and fails closed on any error, non-string
-- result, or wrong length. It never falls back to `math.random`.
--
-- @tparam[opt] table options
-- @tparam[opt] function options.entropy `function(byte_count) -> string` CSPRNG
-- @tparam[opt] function options.clock `function() -> integer` Unix seconds
-- @treturn table an object exposing `generate` and `generate_binary`
function pikaid.new(options)
  if options ~= nil and type(options) ~= "table" then
    fail("invalid_type", "options must be a table or nil, got " .. describe_value(options))
  end

  local provider = entropy.bytes
  local clock = os.time

  if options then
    if options.entropy ~= nil then
      provider = options.entropy
    end

    if options.clock ~= nil then
      clock = options.clock
    end
  end

  if type(provider) ~= "function" then
    fail("invalid_type", "options.entropy must be a function, got " .. describe_value(provider))
  end

  if type(clock) ~= "function" then
    fail("invalid_type", "options.clock must be a function, got " .. describe_value(clock))
  end

  local instance = {}

  --- Generate a pikaid string using this instance's providers.
  -- @tparam[opt] integer timestamp whole Unix seconds
  -- @treturn string a 26-character pikaid
  instance.generate = function(timestamp)
    return generate(provider, clock, timestamp)
  end

  --- Generate a 17-byte binary pikaid using this instance's providers.
  -- @tparam[opt] integer timestamp whole Unix seconds
  -- @treturn string a 17-byte binary pikaid
  instance.generate_binary = function(timestamp)
    return generate_binary(provider, clock, timestamp)
  end

  return instance
end

--- Check only the shape of a value: length and lowercase Base36 alphabet.
--
-- A `true` result is **not** full validity: a 19-digit suffix can still encode
-- more than 96 bits. Use `pikaid.validate` for semantic validation.
--
-- @param value candidate value of any type
-- @treturn boolean whether the value has the pikaid shape
function pikaid.is_well_formed(value)
  return type(value) == "string"
    and #value == STRING_LENGTH
    and value:find("^[0-9a-z]+$") ~= nil
end

--- Parse a pikaid string without raising.
--
-- Nothing is normalized, truncated, or coerced. Invalid input yields `nil`
-- plus a pikaid error object. Use `pikaid.parse` when an error should raise.
--
-- @tparam string value candidate pikaid
-- @treturn table|nil `{ timestamp, randomness, randomness_hex }`, or `nil`
-- @treturn table|nil a pikaid error object on failure
function pikaid.try_parse(value)
  if type(value) ~= "string" then
    return nil, new_error("invalid_type", "expected a string, got " .. describe_value(value))
  end

  if #value ~= STRING_LENGTH then
    return nil, new_error(
      "invalid_length",
      string.format("expected %d characters, got %d", STRING_LENGTH, #value)
    )
  end

  if not value:find("^[0-9a-z]+$") then
    return nil, new_error(
      "invalid_character",
      "expected only lowercase Base36 characters (0-9a-z)"
    )
  end

  local timestamp = base36.decode(value, 1, TIMESTAMP_DIGITS)
  local randomness, reason = base36.decode_randomness(value, TIMESTAMP_DIGITS + 1)

  if not randomness then
    if reason == "overflow" then
      return nil, new_error(
        "randomness_out_of_range",
        "randomness exceeds the 96-bit maximum (2^96 - 1)"
      )
    end

    return nil, new_error("invalid_character", "invalid Base36 character")
  end

  return {
    timestamp = timestamp,
    randomness = randomness,
    randomness_hex = to_hex(randomness),
  }
end

--- Strictly parse a pikaid string, raising on invalid input.
--
-- @tparam string value candidate pikaid
-- @treturn table the parsed fields
function pikaid.parse(value)
  local parsed, parse_error = pikaid.try_parse(value)

  if not parsed then
    error(parse_error, 0)
  end

  return parsed
end

--- Check full semantic validity of a pikaid string.
--
-- @param value candidate value of any type
-- @treturn boolean whether the value is a valid pikaid
function pikaid.validate(value)
  return pikaid.try_parse(value) ~= nil
end

--- Strictly parse a 17-byte binary pikaid.
--
-- @tparam string value candidate binary value
-- @treturn table|nil parsed fields, or `nil` and an error object
function pikaid.try_parse_binary(value)
  if type(value) ~= "string" then
    return nil, new_error("invalid_type", "expected a string, got " .. describe_value(value))
  end

  if #value ~= BINARY_LENGTH then
    return nil, new_error(
      "invalid_length",
      string.format("expected %d bytes, got %d", BINARY_LENGTH, #value)
    )
  end

  local timestamp = decode_binary_timestamp(value)

  if timestamp > MAX_TIMESTAMP then
    return nil, new_error(
      "timestamp_out_of_range",
      string.format(
        "binary timestamp %d exceeds the maximum %d",
        timestamp,
        MAX_TIMESTAMP
      )
    )
  end

  local randomness = value:sub(BINARY_TIMESTAMP_BYTES + 1, BINARY_LENGTH)

  return {
    timestamp = timestamp,
    randomness = randomness,
    randomness_hex = to_hex(randomness),
  }
end

--- Strictly parse a 17-byte binary pikaid, raising on invalid input.
--
-- @tparam string value candidate binary value
-- @treturn table the parsed fields
function pikaid.parse_binary(value)
  local parsed, parse_error = pikaid.try_parse_binary(value)

  if not parsed then
    error(parse_error, 0)
  end

  return parsed
end

--- Check full semantic validity of a 17-byte binary pikaid.
--
-- @param value candidate value of any type
-- @treturn boolean whether the value is a valid binary pikaid
function pikaid.validate_binary(value)
  return pikaid.try_parse_binary(value) ~= nil
end

--- Convert a pikaid string to its 17-byte binary representation.
--
-- @tparam string value a valid pikaid
-- @treturn string exactly 17 bytes
function pikaid.to_binary(value)
  local parsed = pikaid.parse(value)

  return encode_binary_timestamp(parsed.timestamp) .. parsed.randomness
end

--- Convert a 17-byte binary pikaid to its canonical string form.
--
-- @tparam string value a valid 17-byte binary pikaid
-- @treturn string exactly 26 characters
function pikaid.from_binary(value)
  local parsed = pikaid.parse_binary(value)

  return base36.encode(parsed.timestamp, TIMESTAMP_DIGITS)
    .. base36.encode_randomness(parsed.randomness)
end

--- Extract the timestamp from a pikaid string.
--
-- @tparam string value a valid pikaid
-- @treturn integer whole Unix seconds
function pikaid.timestamp(value)
  return pikaid.parse(value).timestamp
end

--- Extract the raw 12 randomness bytes from a pikaid string.
--
-- @tparam string value a valid pikaid
-- @treturn string exactly 12 bytes
function pikaid.randomness(value)
  return pikaid.parse(value).randomness
end

--- Compare two byte strings without locale-dependent collation.
--
-- Lua's `<` operator follows the process locale, which is not guaranteed to be
-- ASCII-compatible. This function compares raw unsigned bytes instead, so the
-- pikaid ordering guarantee holds regardless of `os.setlocale`.
--
-- Valid pikaid values with different timestamps sort chronologically; values
-- sharing a timestamp are ordered by their random suffix, not by generation
-- order.
--
-- @tparam string left left operand
-- @tparam string right right operand
-- @treturn integer `-1`, `0`, or `1`
function pikaid.compare(left, right)
  if type(left) ~= "string" then
    fail("invalid_type", "left operand must be a string, got " .. describe_value(left))
  end

  if type(right) ~= "string" then
    fail("invalid_type", "right operand must be a string, got " .. describe_value(right))
  end

  local shared = math.min(#left, #right)

  for position = 1, shared do
    local left_byte = left:byte(position)
    local right_byte = right:byte(position)

    if left_byte ~= right_byte then
      if left_byte < right_byte then
        return -1
      end
      return 1
    end
  end

  if #left == #right then
    return 0
  end

  if #left < #right then
    return -1
  end

  return 1
end

--- Test whether a value is a pikaid error object.
--
-- @param value value of any type
-- @treturn boolean whether the value is a pikaid error
function pikaid.is_error(value)
  return type(value) == "table" and getmetatable(value) == Error
end

return pikaid
