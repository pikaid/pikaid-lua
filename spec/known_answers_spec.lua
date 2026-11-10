--- Hand-derived known-answer tests.
--
-- These expectations were computed from the pikaid 1.0.4 rules by hand and
-- with an independent Python oracle; none of them is produced by the Lua code
-- under test at assertion time. They pin the exact Base36 anchors, boundary
-- values, and the 96-bit overflow edge.

local pikaid = require("pikaid")
local hex = require("spec.support.hex")

-- Independent rendering of the 5-byte big-endian timestamp field.
local function timestamp_hex(timestamp)
  local bytes = {}

  for position = 5, 1, -1 do
    bytes[position] = string.format("%02x", timestamp % 256)
    timestamp = timestamp // 256
  end

  return table.concat(bytes)
end

local CASES = {
  { name = "zero", timestamp = 0, entropy = "000000000000000000000000",
    id = "00000000000000000000000000", bin_hex = "0000000000000000000000000000000000" },
  { name = "timestamp-1-entropy-1", timestamp = 1, entropy = "000000000000000000000001",
    id = "00000010000000000000000001", bin_hex = "0000000001000000000000000000000001" },
  { name = "timestamp-35", timestamp = 35, entropy = "000000000000000000000000",
    id = "000000z0000000000000000000" },
  { name = "timestamp-36", timestamp = 36, entropy = "000000000000000000000000",
    id = "00000100000000000000000000" },
  { name = "timestamp-1295", timestamp = 1295, entropy = "000000000000000000000000",
    id = "00000zz0000000000000000000" },
  { name = "timestamp-1296", timestamp = 1296, entropy = "000000000000000000000000",
    id = "00001000000000000000000000" },
  { name = "timestamp-46655", timestamp = 46655, entropy = "000000000000000000000000",
    id = "0000zzz0000000000000000000" },
  { name = "timestamp-46656", timestamp = 46656, entropy = "000000000000000000000000",
    id = "00010000000000000000000000" },
  { name = "timestamp-1679615", timestamp = 1679615, entropy = "000000000000000000000000",
    id = "000zzzz0000000000000000000" },
  { name = "timestamp-1679616", timestamp = 1679616, entropy = "000000000000000000000000",
    id = "00100000000000000000000000" },
  { name = "timestamp-1700000000", timestamp = 1700000000, entropy = "00112233445566778899aabb",
    id = "0s44we8002loz3po6mcf6vsn23", bin_hex = "006553f10000112233445566778899aabb" },
  { name = "timestamp-max-minus-one", timestamp = 78364164094, entropy = "000000000000000000000000",
    id = "zzzzzzy0000000000000000000" },
  { name = "timestamp-max", timestamp = 78364164095, entropy = "000000000000000000000000",
    id = "zzzzzzz0000000000000000000", bin_hex = "123ede3fff000000000000000000000000" },
  { name = "entropy-16", timestamp = 0, entropy = "000000000000000000000010",
    id = "0000000000000000000000000g" },
  { name = "entropy-255", timestamp = 0, entropy = "0000000000000000000000ff",
    id = "00000000000000000000000073" },
  { name = "entropy-high-bit", timestamp = 0, entropy = "800000000000000000000000",
    id = "00000003u9haurb9q2x1650zcw" },
  { name = "entropy-high-bit-minus-one", timestamp = 0, entropy = "7fffffffffffffffffffffff",
    id = "00000003u9haurb9q2x1650zcv" },
  { name = "entropy-pattern", timestamp = 0, entropy = "0102030405060708090a0b0c",
    id = "00000000136x1bfzy1wgzvzaj0" },
  { name = "entropy-alternating", timestamp = 0, entropy = "aaaaaaaaaaaa555555555555",
    id = "000000054cn2h0f0xumqyctbv9" },
  { name = "entropy-max", timestamp = 0, entropy = "ffffffffffffffffffffffff",
    id = "00000007oiylpimjg5u2ca1ypr" },
  { name = "official-max-values", timestamp = 78364164095, entropy = "ffffffffffffffffffffffff",
    id = "zzzzzzz7oiylpimjg5u2ca1ypr", bin_hex = "123ede3fffffffffffffffffffffffffff" },
}

return function(t)
  t.describe("known answers", function()
    t.it("matches every hand-derived text and binary anchor", function()
      for _, case in ipairs(CASES) do
        t.equal(#case.id, 26, case.name .. ": id width")

        local binary_hex = case.bin_hex
          or (timestamp_hex(case.timestamp) .. case.entropy)

        t.equal(pikaid.validate(case.id), true, case.name .. ": validate")
        t.equal(pikaid.timestamp(case.id), case.timestamp, case.name .. ": timestamp")
        t.equal(hex.encode(pikaid.randomness(case.id)), case.entropy, case.name .. ": entropy")
        t.equal(pikaid.to_binary(case.id), hex.decode(binary_hex), case.name .. ": to_binary")
        t.equal(pikaid.from_binary(hex.decode(binary_hex)), case.id, case.name .. ": from_binary")
        t.equal(
          pikaid.parse_binary(hex.decode(binary_hex)).timestamp,
          case.timestamp,
          case.name .. ": binary timestamp"
        )
      end
    end)

    t.it("accepts the exact 96-bit maximum but rejects the next value", function()
      local maximum = "0000000" .. "7oiylpimjg5u2ca1ypr"
      local overflow = "0000000" .. "7oiylpimjg5u2ca1yps"

      t.equal(pikaid.validate(maximum), true, "2^96 - 1 is valid")
      t.equal(hex.encode(pikaid.randomness(maximum)), "ffffffffffffffffffffffff", "maximum entropy")

      t.equal(pikaid.is_well_formed(overflow), true, "overflow still has the shape")
      t.equal(pikaid.validate(overflow), false, "2^96 is invalid")

      local raised = t.error_code("randomness_out_of_range", function()
        pikaid.parse(overflow)
      end, "2^96 parse")
      t.ok(raised.message:find("96%-bit") ~= nil, "message mentions the 96-bit limit")

      t.error_code("randomness_out_of_range", function()
        pikaid.parse("0000000" .. string.rep("z", 19))
      end, "all z randomness")
    end)

    t.it("accepts the exact maximum binary timestamp and rejects overflow", function()
      local maximum = hex.decode("123ede3fff" .. string.rep("00", 12))
      local overflow = hex.decode("123ede4000" .. string.rep("00", 12))

      t.equal(#maximum, 17, "maximum binary width")
      t.equal(pikaid.validate_binary(maximum), true, "maximum binary timestamp")
      t.equal(pikaid.timestamp(pikaid.from_binary(maximum)), 78364164095, "maximum binary timestamp value")

      t.equal(pikaid.validate_binary(overflow), false, "timestamp 2^37 is invalid")
      t.error_code("timestamp_out_of_range", function()
        pikaid.parse_binary(overflow)
      end, "overflow binary")

      t.equal(pikaid.validate_binary(hex.decode(string.rep("ff", 17))), false, "all-ones binary")
    end)

    t.it("requires exactly 26 text characters and 17 binary bytes", function()
      t.equal(pikaid.is_well_formed(string.rep("0", 25)), false, "25 characters")
      t.equal(pikaid.is_well_formed(string.rep("0", 27)), false, "27 characters")
      t.equal(pikaid.is_well_formed(string.rep("0", 26)), true, "26 characters")

      t.equal(pikaid.validate_binary(string.rep("\0", 16)), false, "16 binary bytes")
      t.equal(pikaid.validate_binary(string.rep("\0", 18)), false, "18 binary bytes")
      t.equal(pikaid.validate_binary(string.rep("\0", 17)), true, "17 binary bytes")
    end)
  end)
end
