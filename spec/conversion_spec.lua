--- Lossless conversion and ordering property tests.
--
-- The round-trip checks use a deterministic byte generator implemented here,
-- independent of both the library and the reference fixture, so a large number
-- of arbitrary 96-bit values and timestamps are exercised on every Lua version.

local pikaid = require("pikaid")
local hex = require("spec.support.hex")

local MAX_TIMESTAMP = 78364164095
local STATE_MODULUS = 2147483648

return function(t)
  local state = 20261106

  local function next_byte()
    state = (state * 1103515245 + 12345) % STATE_MODULUS
    return (state // 65536) % 256
  end

  local function next_timestamp()
    local value = 0

    for _ = 1, 5 do
      value = value * 256 + next_byte()
    end

    return value % (MAX_TIMESTAMP + 1)
  end

  local function next_entropy()
    local bytes = {}

    for index = 1, 12 do
      bytes[index] = string.char(next_byte())
    end

    return table.concat(bytes)
  end

  t.describe("lossless conversions", function()
    t.it("round-trips deterministic property cases in both directions", function()
      local queue = {}
      local instance = pikaid.new({
        entropy = function(count)
          t.equal(count, 12, "entropy byte count")
          return queue[#queue]
        end,
        clock = function()
          error("clock must not be called when a timestamp is supplied")
        end,
      })

      local previous_id
      local previous_binary
      local previous_timestamp

      for index = 1, 300 do
        local timestamp = next_timestamp()
        local randomness = next_entropy()
        queue[#queue + 1] = randomness

        local id = instance.generate(timestamp)
        local binary = pikaid.to_binary(id)
        local parsed = pikaid.parse(id)
        local parsed_binary = pikaid.parse_binary(binary)

        t.equal(#id, 26, index .. ": text width")
        t.equal(#binary, 17, index .. ": binary width")
        t.equal(pikaid.validate(id), true, index .. ": text validity")
        t.equal(pikaid.validate_binary(binary), true, index .. ": binary validity")
        t.equal(parsed.timestamp, timestamp, index .. ": parsed timestamp")
        t.equal(parsed.randomness, randomness, index .. ": parsed randomness")
        t.equal(parsed.randomness_hex, hex.encode(randomness), index .. ": parsed hex")
        t.equal(parsed_binary.timestamp, timestamp, index .. ": binary timestamp")
        t.equal(parsed_binary.randomness, randomness, index .. ": binary randomness")
        t.equal(pikaid.from_binary(binary), id, index .. ": binary -> text")
        t.equal(pikaid.to_binary(pikaid.from_binary(binary)), binary, index .. ": text -> binary")
        t.equal(pikaid.timestamp(id), timestamp, index .. ": accessor timestamp")
        t.equal(pikaid.randomness(id), randomness, index .. ": accessor randomness")

        if previous_timestamp and timestamp > previous_timestamp then
          t.equal(pikaid.compare(id, previous_id), 1, index .. ": text ordering")
          t.equal(pikaid.compare(binary, previous_binary), 1, index .. ": binary ordering")
        end

        previous_id = id
        previous_binary = binary
        previous_timestamp = timestamp
      end
    end)

    t.it("keeps zeros and the upper boundary exact", function()
      local zeros = "00000000000000000000000000"
      local maximum = "zzzzzzz7oiylpimjg5u2ca1ypr"

      t.equal(hex.encode(pikaid.to_binary(zeros)), string.rep("00", 17), "zero binary")
      t.equal(pikaid.from_binary(string.rep("\0", 17)), zeros, "zero text")

      t.equal(hex.encode(pikaid.to_binary(maximum)), "123ede3fffffffffffffffffffffffffff", "maximum binary")
      t.equal(pikaid.from_binary(hex.decode("123ede3fffffffffffffffffffffffffff")), maximum, "maximum text")
    end)

    t.it("preserves a spread of entropy byte values", function()
      local bytes = {}

      for index = 0, 11 do
        bytes[index + 1] = string.char((index * 23 + 7) % 256)
      end

      local randomness = table.concat(bytes)
      local instance = pikaid.new({
        entropy = function() return randomness end,
        clock = function() return 1234567890 end,
      })

      local id = instance.generate()
      local binary = pikaid.to_binary(id)

      t.equal(pikaid.randomness(id), randomness, "text randomness")
      t.equal(pikaid.parse_binary(binary).randomness, randomness, "binary randomness")
      t.equal(pikaid.from_binary(binary), id, "round trip")
    end)

    t.it("rejects invalid values instead of converting them", function()
      t.error_code("invalid_length", function()
        pikaid.to_binary("0000000000000000000000000")
      end, "short text to binary")

      t.error_code("randomness_out_of_range", function()
        pikaid.to_binary("0000000" .. "7oiylpimjg5u2ca1yps")
      end, "overflow text to binary")

      t.error_code("invalid_length", function()
        pikaid.from_binary(string.rep("\0", 16))
      end, "short binary to text")

      t.error_code("timestamp_out_of_range", function()
        pikaid.from_binary(hex.decode(string.rep("ff", 17)))
      end, "overflow binary to text")
    end)
  end)

  t.describe("comparison", function()
    t.it("compares unsigned bytes, not locale collation", function()
      t.equal(pikaid.compare("", ""), 0, "empty")
      t.equal(pikaid.compare("a", "a"), 0, "equal")
      t.equal(pikaid.compare("a", "b"), -1, "ascending")
      t.equal(pikaid.compare("b", "a"), 1, "descending")
      t.equal(pikaid.compare("a", "aa"), -1, "prefix shorter")
      t.equal(pikaid.compare("aa", "a"), 1, "prefix longer")
      t.equal(pikaid.compare("I", "i"), -1, "uppercase byte before lowercase")
      t.equal(pikaid.compare(string.char(0x7f), string.char(0x80)), -1, "unsigned high bytes")
      t.equal(pikaid.compare("\255", "\1"), 1, "0xff after 0x01")
    end)

    t.it("sorts other timestamps chronologically but does not promise within-second order", function()
      local first = "0s44we8" .. string.rep("0", 19)
      local second = "0s44we9" .. string.rep("0", 19)
      local same_second_low = "0s44we8" .. string.rep("0", 18) .. "z"
      local same_second_high = "0s44we8" .. string.rep("z", 19)

      t.equal(pikaid.validate(first), true, "first valid")
      t.equal(pikaid.validate(second), true, "second valid")
      t.equal(pikaid.compare(first, second), -1, "later second sorts later")
      t.equal(pikaid.compare(second, first), 1, "reverse")
      t.equal(pikaid.compare(same_second_low, same_second_high), -1, "suffix order is byte order")
      t.equal(pikaid.compare(same_second_low, same_second_low), 0, "identity")
    end)

    t.it("rejects non-string operands", function()
      t.error_code("invalid_type", function() pikaid.compare(nil, "a") end, "nil left")
      t.error_code("invalid_type", function() pikaid.compare("a", nil) end, "nil right")
      t.error_code("invalid_type", function() pikaid.compare(1, 2) end, "numbers")
      t.error_code("invalid_type", function() pikaid.compare({}, "a") end, "table")
    end)
  end)
end
