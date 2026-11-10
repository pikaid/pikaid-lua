--- Public API surface, error objects, and locale-independence tests.

local pikaid = require("pikaid")

return function(t)
  t.describe("public API", function()
    t.it("publishes the documented constants", function()
      t.equal(pikaid.VERSION, "1.0.0", "version")
      t.equal(pikaid.STRING_LENGTH, 26, "string length")
      t.equal(pikaid.BINARY_LENGTH, 17, "binary length")
      t.equal(pikaid.TIMESTAMP_DIGITS, 7, "timestamp digits")
      t.equal(pikaid.RANDOMNESS_DIGITS, 19, "randomness digits")
      t.equal(pikaid.ENTROPY_BYTES, 12, "entropy bytes")
      t.equal(pikaid.MAX_TIMESTAMP, 78364164095, "maximum timestamp")
      t.equal(pikaid.MAX_TIMESTAMP, 36 ^ 7 - 1, "maximum timestamp derivation")
    end)

    t.it("exposes the documented functions", function()
      for _, name in ipairs({
        "generate",
        "generate_binary",
        "new",
        "validate",
        "is_well_formed",
        "parse",
        "try_parse",
        "parse_binary",
        "try_parse_binary",
        "validate_binary",
        "to_binary",
        "from_binary",
        "timestamp",
        "randomness",
        "compare",
        "is_error",
      }) do
        t.equal(type(pikaid[name]), "function", name)
      end
    end)

    t.it("parses into an integer timestamp and lowercase hex", function()
      local parsed = pikaid.parse("0s44we8002loz3po6mcf6vsn23")

      t.equal(math.type(parsed.timestamp), "integer", "timestamp subtype")
      t.equal(#parsed.randomness, 12, "randomness width")
      t.equal(parsed.randomness_hex, "00112233445566778899aabb", "randomness hex")
      t.equal(parsed.randomness_hex, parsed.randomness_hex:lower(), "lowercase hex")
      t.equal(#parsed.randomness_hex, 24, "hex width")
    end)

    t.it("returns structured, distinguishable error objects", function()
      local first, first_error = pikaid.try_parse("nope")
      local _, second_error = pikaid.try_parse("nope")

      t.equal(first, nil, "try_parse result")
      t.equal(pikaid.is_error(first_error), true, "is_error on try_parse error")
      t.equal(first_error == second_error, false, "errors are independent")
      t.equal(first_error.code, "invalid_length", "error code")
      t.equal(type(first_error.message), "string", "message type")
      t.equal(tostring(first_error), "pikaid: invalid_length: " .. first_error.message, "tostring")

      local raised = t.raises(function() pikaid.parse("nope") end, "parse raises")
      t.equal(pikaid.is_error(raised), true, "is_error on raised error")
      t.equal(raised.code, "invalid_length", "raised code")
      t.ok(raised.message:find("26", 1, true) ~= nil, "message mentions expected length")

      t.equal(pikaid.is_error(nil), false, "nil")
      t.equal(pikaid.is_error("invalid_length"), false, "string")
      t.equal(pikaid.is_error({}), false, "plain table")
      t.equal(pikaid.is_error({ code = "invalid_length", message = "x" }), false, "table with fields")

      local _, binary_error = pikaid.try_parse_binary("short")
      t.equal(pikaid.is_error(binary_error), true, "binary error")
      t.equal(binary_error.code, "invalid_length", "binary code")
    end)

    t.it("validates constructor options", function()
      local default = pikaid.new()
      t.equal(type(default), "table", "default instance")
      t.equal(type(default.generate), "function", "default generate")
      t.equal(type(default.generate_binary), "function", "default generate_binary")

      local empty = pikaid.new({})
      t.equal(type(empty.generate), "function", "empty options")

      local itself = pikaid.new({ entropy = function() return string.rep("\0", 12) end })
      t.equal(type(itself.generate), "function", "entropy only")

      t.error_code("invalid_type", function() pikaid.new("options") end, "non-table options")
      t.error_code("invalid_type", function() pikaid.new({ entropy = "nope" }) end, "non-function entropy")
      t.error_code("invalid_type", function() pikaid.new({ clock = 0 }) end, "non-function clock")
      t.error_code("invalid_type", function() pikaid.new({ entropy = false }) end, "false entropy")
    end)

    t.it("keeps generation and parsing consistent", function()
      local instance = pikaid.new({
        entropy = function() return string.rep("\170", 12) end,
        clock = function() return 1700000000 end,
      })

      local id = instance.generate()
      local binary = instance.generate_binary()

      t.equal(pikaid.timestamp(id), 1700000000, "text timestamp")
      t.equal(pikaid.parse_binary(binary).timestamp, 1700000000, "binary timestamp")
      t.equal(pikaid.randomness(id), string.rep("\170", 12), "text randomness")
      t.equal(pikaid.parse_binary(binary).randomness, string.rep("\170", 12), "binary randomness")
      t.equal(pikaid.from_binary(pikaid.to_binary(id)), id, "text round trip")
    end)

    t.it("captures provider options at construction time", function()
      local calls = 0
      local options = {
        entropy = function()
          calls = calls + 1
          return string.rep("\0", 12)
        end,
        clock = function() return 0 end,
      }

      local instance = pikaid.new(options)

      options.entropy = function() error("entropy mutated after construction") end
      options.clock = function() error("clock mutated after construction") end

      t.equal(instance.generate(), "00000000000000000000000000", "original providers")
      t.equal(calls, 1, "original provider called")
    end)

    t.it("is independent of the process collation locale", function()
      local original = os.setlocale(nil, "collate")
      local turkish = os.setlocale("tr_TR.UTF-8", "collate") or os.setlocale("tr_TR", "collate")

      local ok, message = pcall(function()
        -- In Turkish collation 'i' sorts before 'I'; pikaid must use byte order.
        t.equal(pikaid.compare("I", "i"), -1, "I before i")
        t.equal(pikaid.compare("i", "I"), 1, "i after I")
        t.equal(pikaid.compare("0s44we8", "0s44we9"), -1, "timestamp order")
        t.equal(pikaid.compare("0s44we8z", "0s44we8a"), 1, "byte order in suffix")
      end)

      if original then
        os.setlocale(original, "collate")
      else
        os.setlocale("C", "collate")
      end

      if turkish == nil then
        -- The locale was unavailable; the assertions still ran under the
        -- process locale, and restore keeps the suite deterministic.
        t.ok(ok, "comparison under the available locale")
      end

      if not ok then
        error(message, 0)
      end
    end)
  end)
end
