--- Executable checks for the documented README workflow.
--
-- The README shows a concrete quick start with a documented sample identifier.
-- These tests run the same operations so a documentation drift fails CI.

local pikaid = require("pikaid")
local hex = require("spec.support.hex")

local SAMPLE = "0s44we8002loz3po6mcf6vsn23"
local SAMPLE_ENTROPY = "00112233445566778899aabb"

return function(t)
  t.describe("README workflow", function()
    t.it("executes the quick-start sequence on its documented sample", function()
      local id = SAMPLE

      t.equal(#id, 26, "sample width")
      t.equal(pikaid.validate(id), true, "validate")
      t.equal(pikaid.is_well_formed(id), true, "shape")
      t.equal(pikaid.timestamp(id), 1700000000, "timestamp")
      t.equal(hex.encode(pikaid.randomness(id)), SAMPLE_ENTROPY, "randomness")

      local parsed = pikaid.parse(id)
      t.equal(parsed.timestamp, 1700000000, "parsed timestamp")
      t.equal(parsed.randomness_hex, SAMPLE_ENTROPY, "parsed hex")

      local binary = pikaid.to_binary(id)
      t.equal(#binary, 17, "binary width")
      t.equal(pikaid.from_binary(binary), id, "round trip")

      local ok, parse_error = pikaid.try_parse("not a pikaid")
      t.equal(ok, nil, "try_parse result")
      t.equal(parse_error.code, "invalid_length", "try_parse code")
      t.ok(tostring(parse_error):find("^pikaid: invalid_length: ") ~= nil, "error rendering")
    end)

    t.it("runs the documented injectable-provider example", function()
      local ids = pikaid.new({
        entropy = function(byte_count)
          t.equal(byte_count, 12, "provider byte count")
          return hex.decode(SAMPLE_ENTROPY)
        end,
        clock = function()
          return 1700000000
        end,
      })

      t.equal(ids.generate(), SAMPLE, "documented identifier")
      t.equal(hex.encode(ids.generate_binary()), "006553f100" .. SAMPLE_ENTROPY, "documented binary")
    end)

    t.it("agrees with the documented constants table", function()
      t.equal(pikaid.VERSION, "1.0.0", "VERSION")
      t.equal(pikaid.STRING_LENGTH, 26, "STRING_LENGTH")
      t.equal(pikaid.BINARY_LENGTH, 17, "BINARY_LENGTH")
      t.equal(pikaid.TIMESTAMP_DIGITS, 7, "TIMESTAMP_DIGITS")
      t.equal(pikaid.RANDOMNESS_DIGITS, 19, "RANDOMNESS_DIGITS")
      t.equal(pikaid.ENTROPY_BYTES, 12, "ENTROPY_BYTES")
      t.equal(pikaid.MAX_TIMESTAMP, 78364164095, "MAX_TIMESTAMP")
    end)
  end)
end
