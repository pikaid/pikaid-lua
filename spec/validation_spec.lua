--- Strict validation and rejection tests.
--
-- pikaid must never coerce, trim, case-fold, or truncate. These tests pin the
-- exact error codes and the distinction between a shape check and full
-- semantic validation.

local pikaid = require("pikaid")

local function repeated(character, count)
  return string.rep(character, count)
end

local STRING_CASES = {
  { name = "empty", value = "", code = "invalid_length" },
  { name = "25 characters", value = repeated("0", 25), code = "invalid_length" },
  { name = "27 characters", value = repeated("0", 27), code = "invalid_length" },
  { name = "long value", value = repeated("0", 128), code = "invalid_length" },
  { name = "uppercase suffix", value = repeated("0", 25) .. "A", code = "invalid_character" },
  { name = "uppercase timestamp", value = "ZZZZZZZ" .. repeated("0", 19), code = "invalid_character" },
  { name = "dash", value = repeated("0", 25) .. "-", code = "invalid_character" },
  { name = "underscore", value = repeated("0", 25) .. "_", code = "invalid_character" },
  { name = "space", value = repeated("0", 25) .. " ", code = "invalid_character" },
  { name = "plus", value = repeated("0", 25) .. "+", code = "invalid_character" },
  { name = "slash", value = repeated("0", 25) .. "/", code = "invalid_character" },
  { name = "colon", value = repeated("0", 25) .. ":", code = "invalid_character" },
  { name = "newline", value = repeated("0", 25) .. "\n", code = "invalid_character" },
  { name = "tab", value = repeated("0", 25) .. "\t", code = "invalid_character" },
  { name = "carriage return", value = repeated("0", 25) .. "\r", code = "invalid_character" },
  { name = "CRLF", value = repeated("0", 24) .. "\r\n", code = "invalid_character" },
  {
    name = "zero-width space",
    value = repeated("0", 23) .. string.char(0xE2, 0x80, 0x8B),
    code = "invalid_character",
  },
  { name = "NUL byte", value = repeated("0", 25) .. "\0", code = "invalid_character" },
  { name = "UTF-8 letter", value = repeated("0", 24) .. string.char(0xC3, 0xA9), code = "invalid_character" },
  { name = "emoji", value = repeated("0", 22) .. string.char(0xF0, 0x9F, 0x98, 0x80), code = "invalid_character" },
  { name = "leading whitespace", value = " " .. repeated("0", 25), code = "invalid_character" },
  { name = "randomness 2^96", value = "0000000" .. "7oiylpimjg5u2ca1yps", code = "randomness_out_of_range" },
  { name = "randomness all z", value = "0000000" .. repeated("z", 19), code = "randomness_out_of_range" },
}

local BINARY_CASES = {
  { name = "empty", value = "", code = "invalid_length" },
  { name = "16 bytes", value = repeated("\0", 16), code = "invalid_length" },
  { name = "18 bytes", value = repeated("\0", 18), code = "invalid_length" },
  { name = "34 bytes", value = repeated("\0", 34), code = "invalid_length" },
  {
    name = "timestamp 2^37",
    value = string.char(0x12, 0x3e, 0xde, 0x40, 0x00) .. repeated("\0", 12),
    code = "timestamp_out_of_range",
  },
  { name = "timestamp 2^40 - 1", value = repeated("\255", 17), code = "timestamp_out_of_range" },
}

local NON_STRINGS = {
  { name = "nil", value = nil },
  { name = "true", value = true },
  { name = "false", value = false },
  { name = "integer", value = 0 },
  { name = "float", value = 1.5 },
  { name = "table", value = {} },
  { name = "function", value = function() end },
}

return function(t)
  t.describe("strict text validation", function()
    t.it("rejects invalid lengths and characters with exact codes", function()
      for _, case in ipairs(STRING_CASES) do
        t.equal(pikaid.validate(case.value), false, case.name .. ": validate")

        local parsed, parse_error = pikaid.try_parse(case.value)
        t.equal(parsed, nil, case.name .. ": try_parse result")
        t.equal(parse_error.code, case.code, case.name .. ": try_parse code")

        local raised = t.error_code(case.code, function()
          pikaid.parse(case.value)
        end, case.name .. ": parse")

        t.equal(tostring(raised):sub(1, 7), "pikaid:", case.name .. ": error prefix")
        t.ok(#raised.message > 0, case.name .. ": error message")
      end
    end)

    t.it("distinguishes shape from semantic validity", function()
      local overflow = "0000000" .. "7oiylpimjg5u2ca1yps"

      t.equal(pikaid.is_well_formed(overflow), true, "overflow has the shape")
      t.equal(pikaid.validate(overflow), false, "overflow is not valid")

      t.equal(pikaid.is_well_formed("00000000000000000000000000"), true, "zero id shape")
      t.equal(pikaid.validate("00000000000000000000000000"), true, "zero id validity")

      for _, case in ipairs(STRING_CASES) do
        if case.code == "invalid_length" or case.code == "invalid_character" then
          t.equal(pikaid.is_well_formed(case.value), false, case.name .. ": shape")
        end
      end
    end)

    t.it("rejects non-string input without calling string methods", function()
      for _, case in ipairs(NON_STRINGS) do
        t.equal(pikaid.validate(case.value), false, case.name .. ": validate")
        t.equal(pikaid.is_well_formed(case.value), false, case.name .. ": shape")

        local parsed, parse_error = pikaid.try_parse(case.value)
        t.equal(parsed, nil, case.name .. ": try_parse result")
        t.equal(parse_error.code, "invalid_type", case.name .. ": try_parse code")

        t.error_code("invalid_type", function()
          pikaid.parse(case.value)
        end, case.name .. ": parse")

        t.error_code("invalid_type", function()
          pikaid.to_binary(case.value)
        end, case.name .. ": to_binary")

        t.error_code("invalid_type", function()
          pikaid.timestamp(case.value)
        end, case.name .. ": timestamp")

        t.error_code("invalid_type", function()
          pikaid.randomness(case.value)
        end, case.name .. ": randomness")
      end
    end)

    t.it("does not normalize case, whitespace, or truncation", function()
      local upper = "0S44WE8002LOZ3PO6MCF6VSN23"

      t.equal(#upper, 26, "uppercase fixture width")
      t.equal(pikaid.validate(upper), false, "uppercase rejected")
      t.equal(pikaid.validate(upper:lower()), true, "only lowercased form is valid")

      local padded = " " .. "0000000000000000000000000"
      t.equal(#padded, 26, "padded fixture width")
      t.equal(pikaid.validate(padded), false, "space is not trimmed")

      local truncated = "0s44we8002loz3po6mcf6vsn2"
      t.equal(#truncated, 25, "truncated width")
      t.equal(pikaid.validate(truncated), false, "truncation is not padded")
    end)
  end)

  t.describe("strict binary validation", function()
    t.it("rejects invalid lengths and timestamp overflow with exact codes", function()
      for _, case in ipairs(BINARY_CASES) do
        t.equal(pikaid.validate_binary(case.value), false, case.name .. ": validate_binary")

        local parsed, parse_error = pikaid.try_parse_binary(case.value)
        t.equal(parsed, nil, case.name .. ": try_parse_binary result")
        t.equal(parse_error.code, case.code, case.name .. ": try_parse_binary code")

        t.error_code(case.code, function()
          pikaid.parse_binary(case.value)
        end, case.name .. ": parse_binary")

        t.error_code(case.code, function()
          pikaid.from_binary(case.value)
        end, case.name .. ": from_binary")
      end
    end)

    t.it("rejects non-string binary input", function()
      for _, case in ipairs(NON_STRINGS) do
        t.equal(pikaid.validate_binary(case.value), false, case.name .. ": validate_binary")

        local parsed, parse_error = pikaid.try_parse_binary(case.value)
        t.equal(parsed, nil, case.name .. ": try_parse_binary result")
        t.equal(parse_error.code, "invalid_type", case.name .. ": code")

        t.error_code("invalid_type", function()
          pikaid.parse_binary(case.value)
        end, case.name .. ": parse_binary")
      end
    end)

    t.it("accepts every byte value in the randomness field", function()
      local binary = string.char(0x00, 0x00, 0x00, 0x00, 0x00)
        .. string.char(0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB)

      t.equal(#binary, 17, "width")
      t.equal(pikaid.validate_binary(binary), true, "binary with high bytes")
      t.equal(pikaid.parse_binary(binary).timestamp, 0, "timestamp")
    end)
  end)
end
