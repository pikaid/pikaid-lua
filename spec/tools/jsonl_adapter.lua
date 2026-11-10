--- Test-only JSON-Lines adapter for the official PikaID conformance suite.
--
-- This file is NOT part of the installed library. It implements only the wire
-- protocol in `pikaid-specs/conformance/docs/JSONL_ADAPTER_PROTOCOL.md` and
-- delegates every semantic operation to the real public `pikaid` module:
--
--   generate_string                  -> pikaid.generate()
--   text_to_binary                   -> pikaid.to_binary(text)
--   binary_to_text                   -> pikaid.from_binary(bytes)
--   boolean_validation               -> pikaid.validate(text)
--   format_only_validation           -> pikaid.is_well_formed(text)
--   parse_components                 -> pikaid.parse(text)
--   generate_with_timestamp          -> pikaid.generate(timestamp)
--   generate_binary                  -> pikaid.generate_binary()
--   generate_binary_with_timestamp   -> pikaid.generate_binary(timestamp)
--   public_compare                   -> pikaid.compare(a, b)
--
-- It deliberately contains no Base36 codec, validator, generator or randomness
-- source of its own. Hexadecimal conversion and JSON serialization are pure
-- transport concerns; all PikaID decisions come from the library.

local script_source = debug.getinfo(1, "S").source
local script_path = script_source:sub(1, 1) == "@" and script_source:sub(2) or script_source
local script_dir = script_path:match("^(.*)[/\\]") or "."
local root = script_dir .. "/../.."

package.path = table.concat({
  root .. "/src/?.lua",
  root .. "/src/?/init.lua",
  root .. "/?.lua",
  root .. "/?/init.lua",
  package.path,
}, ";")

local pikaid = require("pikaid")
local json = require("spec.support.json")

local PROTOCOL_VERSION = 1

-- Only capabilities that are backed by a real public API are advertised.
-- `parse_datetime` is omitted because the library exposes no datetime helper,
-- and `csprng_failure_injection` is omitted because there is no public RNG
-- fault seam. Hiding or inventing either would misrepresent the library.
local CAPABILITIES = {
  "generate_string",
  "text_to_binary",
  "binary_to_text",
  "boolean_validation",
  "format_only_validation",
  "parse_components",
  "generate_with_timestamp",
  "generate_binary",
  "generate_binary_with_timestamp",
  "public_compare",
}

local array_mt = { __jsontype = "array" }

local function array(values)
  return setmetatable(values, array_mt)
end

local json_escapes = {
  ['"'] = '\\"',
  ["\\"] = "\\\\",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
}

local function encode_string(value)
  local escaped = value:gsub('[%z\1-\31\\"]', function(character)
    return json_escapes[character] or string.format("\\u%04x", character:byte())
  end)

  return '"' .. escaped .. '"'
end

local encode_value

local function encode_table(value)
  if getmetatable(value) == array_mt then
    local items = {}

    for index = 1, #value do
      items[index] = encode_value(value[index])
    end

    return "[" .. table.concat(items, ",") .. "]"
  end

  local keys = {}

  for key in pairs(value) do
    if type(key) ~= "string" then
      error("JSON object keys must be strings")
    end
    keys[#keys + 1] = key
  end

  table.sort(keys)

  local fields = {}

  for index = 1, #keys do
    local key = keys[index]
    fields[index] = encode_string(key) .. ":" .. encode_value(value[key])
  end

  return "{" .. table.concat(fields, ",") .. "}"
end

encode_value = function(value)
  local kind = type(value)

  if value == nil then
    return "null"
  elseif kind == "boolean" then
    return value and "true" or "false"
  elseif kind == "number" then
    if math.type(value) == "integer" then
      return tostring(value)
    end
    error("refusing to serialize a non-integer JSON number")
  elseif kind == "string" then
    return encode_string(value)
  elseif kind == "table" then
    return encode_table(value)
  end

  error("cannot serialize a " .. kind .. " as JSON")
end

local function is_integer(value)
  return type(value) == "number" and math.type(value) == "integer"
end

local function bytes_to_hex(value)
  local bytes = {}

  for index = 1, #value do
    bytes[index] = string.format("%02x", value:byte(index))
  end

  return table.concat(bytes)
end

local function hex_to_bytes(value)
  if type(value) ~= "string" or #value % 2 ~= 0 or value:find("[^0-9a-f]") then
    return nil
  end

  local bytes = {}

  for index = 1, #value, 2 do
    bytes[#bytes + 1] = string.char(tonumber(value:sub(index, index + 1), 16))
  end

  return table.concat(bytes)
end

local function success(request_id, value)
  return { request_id = request_id, ok = true, value = value }
end

local function rejection(request_id, category, message)
  return {
    request_id = request_id,
    ok = false,
    error = { category = category, message = message },
  }
end

-- Only the library's documented validation failures are `invalid_input`.
-- Anything else (including a timer or allocator failure) is `internal_error`.
local function classify_validation_error(err)
  if pikaid.is_error(err) then
    return "invalid_input", err.message
  end

  return "internal_error", tostring(err)
end

-- Generation can fail for input reasons (an explicit timestamp outside the
-- supported range) or for environment reasons (CSPRNG/clock unavailable).
-- A CSPRNG failure must never be disguised as input validation.
local function classify_generation_error(err)
  if pikaid.is_error(err) then
    if err.code == "entropy_unavailable" then
      return "entropy_unavailable", err.message
    end

    if err.code == "timestamp_out_of_range" or err.code == "invalid_timestamp" then
      return "invalid_input", err.message
    end

    return "internal_error", err.message
  end

  return "internal_error", tostring(err)
end

local function require_string(arguments, name)
  local value = arguments[name]

  if type(value) ~= "string" then
    return nil, string.format("%s must be a string", name)
  end

  return value
end

local function require_integer(arguments, name)
  local value = arguments[name]

  if not is_integer(value) then
    return nil, string.format("%s must be an integer", name)
  end

  return value
end

-- Each handler returns (value) on success or (nil, category, message).
local handlers = {}

handlers.hello = function()
  return {
    protocol_version = PROTOCOL_VERSION,
    capabilities = array(CAPABILITIES),
  }
end

handlers.generate_string = function()
  local ok, value = pcall(pikaid.generate)

  if not ok then
    return nil, classify_generation_error(value)
  end

  return value
end

handlers.text_to_binary = function(arguments)
  local text, message = require_string(arguments, "text")

  if not text then
    return nil, "invalid_input", message
  end

  local ok, bytes = pcall(pikaid.to_binary, text)

  if not ok then
    return nil, classify_validation_error(bytes)
  end

  return bytes_to_hex(bytes)
end

handlers.binary_to_text = function(arguments)
  local bytes = hex_to_bytes(arguments.binary_hex)

  if not bytes then
    return nil, "invalid_input", "binary_hex must be even-length lowercase hexadecimal"
  end

  local ok, text = pcall(pikaid.from_binary, bytes)

  if not ok then
    return nil, classify_validation_error(text)
  end

  return text
end

handlers.boolean_validation = function(arguments)
  local text, message = require_string(arguments, "text")

  if not text then
    return nil, "invalid_input", message
  end

  return pikaid.validate(text)
end

handlers.format_only_validation = function(arguments)
  local text, message = require_string(arguments, "text")

  if not text then
    return nil, "invalid_input", message
  end

  return pikaid.is_well_formed(text)
end

handlers.parse_components = function(arguments)
  local text, message = require_string(arguments, "text")

  if not text then
    return nil, "invalid_input", message
  end

  local ok, parsed = pcall(pikaid.parse, text)

  if not ok then
    return nil, classify_validation_error(parsed)
  end

  return {
    timestamp_seconds = parsed.timestamp,
    randomness_hex = parsed.randomness_hex,
  }
end

handlers.generate_with_timestamp = function(arguments)
  local timestamp, message = require_integer(arguments, "timestamp_seconds")

  if timestamp == nil then
    return nil, "invalid_input", message
  end

  local ok, value = pcall(pikaid.generate, timestamp)

  if not ok then
    return nil, classify_generation_error(value)
  end

  return value
end

handlers.generate_binary = function()
  local ok, value = pcall(pikaid.generate_binary)

  if not ok then
    return nil, classify_generation_error(value)
  end

  return bytes_to_hex(value)
end

handlers.generate_binary_with_timestamp = function(arguments)
  local timestamp, message = require_integer(arguments, "timestamp_seconds")

  if timestamp == nil then
    return nil, "invalid_input", message
  end

  local ok, value = pcall(pikaid.generate_binary, timestamp)

  if not ok then
    return nil, classify_generation_error(value)
  end

  return bytes_to_hex(value)
end

handlers.public_compare = function(arguments)
  local a, message_a = require_string(arguments, "a")

  if not a then
    return nil, "invalid_input", message_a
  end

  local b, message_b = require_string(arguments, "b")

  if not b then
    return nil, "invalid_input", message_b
  end

  local ok, value = pcall(pikaid.compare, a, b)

  if not ok then
    return nil, classify_validation_error(value)
  end

  return value
end

local function handle_request(request)
  if type(request) ~= "table" then
    return rejection(0, "internal_error", "request must be a JSON object")
  end

  local request_id = request.request_id

  if not is_integer(request_id) then
    return rejection(0, "internal_error", "request_id must be an integer")
  end

  local operation = request.operation

  if type(operation) ~= "string" then
    return rejection(request_id, "internal_error", "operation must be a string")
  end

  local arguments = request.arguments

  if arguments == nil then
    arguments = {}
  elseif type(arguments) ~= "table" then
    return rejection(request_id, "invalid_input", "arguments must be a JSON object")
  end

  local handler = handlers[operation]

  if not handler then
    return rejection(request_id, "unsupported_operation", "unknown operation: " .. operation)
  end

  local ok, value, category, message = pcall(handler, arguments)

  if not ok then
    return rejection(request_id, "internal_error", "adapter exception: " .. tostring(value))
  end

  if category then
    return rejection(request_id, category, message)
  end

  return success(request_id, value)
end

for line in io.stdin:lines() do
  local decoded_ok, request = pcall(json.decode, line)
  local response

  if decoded_ok then
    local handled_ok, handled = pcall(handle_request, request)

    if handled_ok then
      response = handled
    else
      response = rejection(0, "internal_error", "adapter exception: " .. tostring(handled))
    end
  else
    response = rejection(0, "internal_error", "malformed request JSON: " .. tostring(request))
  end

  local encoded_ok, encoded = pcall(encode_value, response)

  if not encoded_ok then
    io.stderr:write("jsonl_adapter: cannot encode response: " .. tostring(encoded) .. "\n")
    os.exit(1)
  end

  io.stdout:write(encoded, "\n")
  io.stdout:flush()
end
