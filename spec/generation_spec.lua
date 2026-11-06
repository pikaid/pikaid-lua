--- Generation, entropy-provider, and clock tests.
--
-- The library must draw exactly 12 bytes from a cryptographic provider, fail
-- closed on any provider or clock failure, and never fall back to a weak PRNG.

local pikaid = require("pikaid")
local entropy = require("pikaid.entropy")
local hex = require("spec.support.hex")

local FIXED = string.char(0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB)

return function(t)
  t.describe("generation", function()
    t.it("generates valid text and binary identifiers from the system CSPRNG", function()
      local before = os.time()
      local id = pikaid.generate()
      local binary = pikaid.generate_binary()
      local after = os.time()

      t.equal(#id, 26, "text width")
      t.equal(#binary, 17, "binary width")
      t.equal(pikaid.validate(id), true, "text validity")
      t.equal(pikaid.validate_binary(binary), true, "binary validity")

      local timestamp = pikaid.timestamp(id)
      t.ok(timestamp >= before - 1 and timestamp <= after + 1, "timestamp is current")

      local binary_timestamp = pikaid.parse_binary(binary).timestamp
      t.ok(binary_timestamp >= before - 1 and binary_timestamp <= after + 1, "binary timestamp is current")

      t.equal(#pikaid.randomness(id), 12, "text randomness width")
      t.equal(#pikaid.parse_binary(binary).randomness, 12, "binary randomness width")
    end)

    t.it("accepts an explicit timestamp and keeps it exact", function()
      local id = pikaid.generate(1700000000)
      local binary = pikaid.generate_binary(1700000000)

      t.equal(pikaid.timestamp(id), 1700000000, "text timestamp")
      t.equal(pikaid.parse_binary(binary).timestamp, 1700000000, "binary timestamp")
      t.equal(pikaid.validate(id), true, "text validity")
      t.equal(pikaid.validate_binary(binary), true, "binary validity")

      t.equal(pikaid.timestamp(pikaid.generate(0)), 0, "zero timestamp")
      t.equal(pikaid.timestamp(pikaid.generate(pikaid.MAX_TIMESTAMP)), pikaid.MAX_TIMESTAMP, "maximum timestamp")
    end)

    t.it("uses the injected provider and clock", function()
      local calls = 0
      local clock_calls = 0
      local instance = pikaid.new({
        entropy = function(count)
          calls = calls + 1
          t.equal(count, 12, "provider byte count")
          return FIXED
        end,
        clock = function()
          clock_calls = clock_calls + 1
          return 1700000000
        end,
      })

      local id = instance.generate()
      t.equal(id, "0s44we8" .. "002loz3po6mcf6vsn23", "deterministic text")
      t.equal(calls, 1, "one entropy call")
      t.equal(clock_calls, 1, "one clock call")

      local binary = instance.generate_binary()
      t.equal(hex.encode(binary), "006553f100" .. "00112233445566778899aabb", "deterministic binary")
      t.equal(calls, 2, "second entropy call")
      t.equal(clock_calls, 2, "second clock call")

      local explicit = instance.generate(1234567890)
      t.equal(calls, 3, "explicit timestamp still draws entropy")
      t.equal(clock_calls, 2, "explicit timestamp bypasses the clock")
      t.equal(pikaid.timestamp(explicit), 1234567890, "explicit timestamp value")
    end)

    t.it("fails closed when the entropy provider fails", function()
      local failures = {
        {
          name = "raises",
          provider = function() error("entropy backend offline") end,
        },
        {
          name = "returns nil",
          provider = function() return nil end,
        },
        {
          name = "returns number",
          provider = function() return 42 end,
        },
        {
          name = "returns table",
          provider = function() return {} end,
        },
        {
          name = "returns empty string",
          provider = function() return "" end,
        },
        {
          name = "returns 11 bytes",
          provider = function() return string.rep("\0", 11) end,
        },
        {
          name = "returns 13 bytes",
          provider = function() return string.rep("\0", 13) end,
        },
      }

      for _, failure in ipairs(failures) do
        local instance = pikaid.new({ entropy = failure.provider, clock = function() return 0 end })

        t.error_code("entropy_unavailable", function()
          instance.generate()
        end, failure.name .. ": generate")

        t.error_code("entropy_unavailable", function()
          instance.generate_binary()
        end, failure.name .. ": generate_binary")
      end
    end)

    t.it("fails closed when the clock fails or returns a non-integer", function()
      local clock_cases = {
        { name = "raises", clock = function() error("clock unavailable") end, code = "clock_unavailable" },
        { name = "returns string", clock = function() return "1700000000" end, code = "invalid_timestamp" },
        { name = "returns float", clock = function() return 1700000000.5 end, code = "invalid_timestamp" },
        { name = "returns nil", clock = function() return nil end, code = "invalid_timestamp" },
        { name = "returns negative", clock = function() return -1 end, code = "timestamp_out_of_range" },
        {
          name = "returns too large",
          clock = function() return pikaid.MAX_TIMESTAMP + 1 end,
          code = "timestamp_out_of_range",
        },
      }

      for _, case in ipairs(clock_cases) do
        local instance = pikaid.new({ entropy = function() return FIXED end, clock = case.clock })

        t.error_code(case.code, function()
          instance.generate()
        end, case.name .. ": generate")

        t.error_code(case.code, function()
          instance.generate_binary()
        end, case.name .. ": generate_binary")
      end
    end)

    t.it("rejects invalid explicit timestamps", function()
      local cases = {
        { name = "negative", value = -1, code = "timestamp_out_of_range" },
        { name = "above maximum", value = pikaid.MAX_TIMESTAMP + 1, code = "timestamp_out_of_range" },
        { name = "float", value = 1.5, code = "invalid_timestamp" },
        { name = "string", value = "1700000000", code = "invalid_timestamp" },
        { name = "boolean", value = true, code = "invalid_timestamp" },
        { name = "table", value = {}, code = "invalid_timestamp" },
      }

      for _, case in ipairs(cases) do
        t.error_code(case.code, function()
          pikaid.generate(case.value)
        end, case.name .. ": generate")

        t.error_code(case.code, function()
          pikaid.generate_binary(case.value)
        end, case.name .. ": generate_binary")
      end
    end)

    t.it("never falls back to math.random", function()
      local original = math.random
      rawset(math, "random", function()
        error("math.random must not be used for pikaid generation")
      end)

      local ok, result = pcall(function()
        local instance = pikaid.new({
          entropy = function() return FIXED end,
          clock = function() return 0 end,
        })
        return instance.generate()
      end)

      rawset(math, "random", original)

      t.equal(ok, true, "stub generation succeeded")
      t.equal(pikaid.validate(result), true, "stub identifier is valid")
    end)

    t.it("produces independent instances", function()
      local zeros = pikaid.new({
        entropy = function() return string.rep("\0", 12) end,
        clock = function() return 0 end,
      })
      local ones = pikaid.new({
        entropy = function() return string.rep("\255", 12) end,
        clock = function() return 0 end,
      })

      t.equal(zeros.generate(), "00000000000000000000000000", "zero instance")
      t.equal(ones.generate(), "00000007oiylpimjg5u2ca1ypr", "ones instance")
    end)
  end)

  t.describe("default entropy provider", function()
    t.it("reads the requested byte count from the operating system device", function()
      local original = entropy.DEVICE

      local ok, data = pcall(entropy.bytes, 12)

      entropy.DEVICE = original

      t.equal(ok, true, "device read succeeded")
      t.equal(#data, 12, "byte count")
      t.equal(entropy.BYTES, 12, "documented byte count")
    end)

    t.it("raises when the device cannot be opened", function()
      local original = entropy.DEVICE
      entropy.DEVICE = "/nonexistent/pikaid-entropy-device"

      local ok, message = pcall(entropy.bytes, 12)

      entropy.DEVICE = original

      t.equal(ok, false, "raised")
      t.ok(tostring(message):find("cannot open", 1, true) ~= nil, "message mentions opening")
    end)

    t.it("raises when the device yields no data", function()
      local original = entropy.DEVICE
      entropy.DEVICE = "/dev/null"

      local ok, message = pcall(entropy.bytes, 12)

      entropy.DEVICE = original

      t.equal(ok, false, "raised")
      t.ok(tostring(message):find("cannot read", 1, true) ~= nil, "message mentions reading")
    end)

    t.it("raises when the device yields fewer bytes than requested", function()
      local original = entropy.DEVICE
      local path = os.tmpname()
      local file = assert(io.open(path, "wb"))
      file:write("abcde")
      file:close()

      entropy.DEVICE = path

      local ok, message = pcall(entropy.bytes, 12)

      entropy.DEVICE = original
      os.remove(path)

      t.equal(ok, false, "raised")
      t.ok(tostring(message):find("short read", 1, true) ~= nil, "message mentions a short read")
    end)
  end)
end
