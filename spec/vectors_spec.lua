--- Conformance tests driven by the official pikaid interoperability fixtures.
--
-- The JSON file is vendored unmodified from pikaid-php v1.2.0; see
-- spec/vectors/README.md. Every valid and invalid fixture entry is exercised.

local json = require("spec.support.json")
local hex = require("spec.support.hex")
local pikaid = require("pikaid")

local VECTOR_PATH = "spec/vectors/pikaid-v1.json"

local function load_vectors()
  local file, open_error = io.open(VECTOR_PATH, "rb")

  if not file then
    error(string.format("cannot open %s: %s", VECTOR_PATH, tostring(open_error)), 0)
  end

  local text = file:read("*a")
  file:close()

  return json.decode(text)
end

local function read_json(path)
  local file = assert(io.open(path, "rb"), "cannot open " .. path)
  local text = file:read("*a")
  file:close()
  return json.decode(text)
end

return function(t)
  local vectors = load_vectors()

  t.describe("official pikaid fixtures", function()
    t.it("declares the 1.0.4 metadata and expected widths", function()
      t.equal(vectors.meta.spec_revision, "1.0.4", "spec revision")
      t.equal(vectors.meta.identifier_format, "immutable and unversioned", "format status")
      t.equal(vectors.meta.string_length, 26, "string length")
      t.equal(vectors.meta.timestamp.max, 78364164095, "timestamp maximum")
      t.equal(vectors.meta.entropy.bytes, 12, "entropy bytes")
      t.equal(vectors.meta.binary.bytes, 17, "binary bytes")
      t.equal(#vectors.valid, 4, "valid fixture count")
      t.equal(#vectors.invalid.string, 6, "invalid string fixture count")
      t.equal(#vectors.invalid.binary, 4, "invalid binary fixture count")
    end)

    t.it("matches every valid fixture in both representations", function()
      for _, vector in ipairs(vectors.valid) do
        t.equal(pikaid.validate(vector.id), true, vector.name .. ": validate")
        t.equal(pikaid.is_well_formed(vector.id), true, vector.name .. ": shape")

        local parsed = pikaid.parse(vector.id)
        t.equal(parsed.timestamp, vector.timestamp, vector.name .. ": timestamp")
        t.equal(parsed.randomness_hex, vector.entropy_hex, vector.name .. ": randomness hex")
        t.equal(hex.encode(parsed.randomness), vector.entropy_hex, vector.name .. ": randomness bytes")

        local binary = pikaid.to_binary(vector.id)
        t.equal(#binary, 17, vector.name .. ": binary length")
        t.equal(hex.encode(binary), vector.bin_hex, vector.name .. ": binary hex")

        local reparsed = pikaid.parse_binary(binary)
        t.equal(reparsed.timestamp, vector.timestamp, vector.name .. ": binary timestamp")
        t.equal(reparsed.randomness_hex, vector.entropy_hex, vector.name .. ": binary randomness")
        t.equal(pikaid.from_binary(binary), vector.id, vector.name .. ": binary to string")

        t.equal(pikaid.timestamp(vector.id), vector.timestamp, vector.name .. ": accessor timestamp")
        t.equal(hex.encode(pikaid.randomness(vector.id)), vector.entropy_hex, vector.name .. ": accessor randomness")
      end
    end)

    t.it("rejects every invalid string fixture with a precise error code", function()
      local expected_codes = {
        ["too-short"] = "invalid_length",
        ["too-long"] = "invalid_length",
        ["uppercase"] = "invalid_character",
        ["invalid-char-dash"] = "invalid_character",
        ["non-base36"] = "invalid_character",
        ["entropy-overflow"] = "randomness_out_of_range",
      }

      for _, vector in ipairs(vectors.invalid.string) do
        local code = assert(expected_codes[vector.name], "unmapped fixture " .. vector.name)

        t.equal(pikaid.validate(vector.id), false, vector.name .. ": validate")
        t.equal(pikaid.is_well_formed(vector.id), vector.name == "entropy-overflow", vector.name .. ": shape")
        t.error_code(code, function() pikaid.parse(vector.id) end, vector.name .. ": parse")
        t.error_code(code, function() pikaid.to_binary(vector.id) end, vector.name .. ": to_binary")

        local parsed, parse_error = pikaid.try_parse(vector.id)
        t.equal(parsed, nil, vector.name .. ": try_parse result")
        t.equal(parse_error.code, code, vector.name .. ": try_parse code")
      end
    end)

    t.it("rejects every invalid binary fixture with a precise error code", function()
      local expected_codes = {
        ["too-short"] = "invalid_length",
        ["too-long"] = "invalid_length",
        ["timestamp-overflow"] = "timestamp_out_of_range",
        ["timestamp-overflow-max-40-bit"] = "timestamp_out_of_range",
      }

      for _, vector in ipairs(vectors.invalid.binary) do
        local code = assert(expected_codes[vector.name], "unmapped fixture " .. vector.name)
        local binary = hex.decode(vector.bin_hex)

        t.equal(pikaid.validate_binary(binary), false, vector.name .. ": validate_binary")
        t.error_code(code, function() pikaid.parse_binary(binary) end, vector.name .. ": parse_binary")
        t.error_code(code, function() pikaid.from_binary(binary) end, vector.name .. ": from_binary")

        local parsed, parse_error = pikaid.try_parse_binary(binary)
        t.equal(parsed, nil, vector.name .. ": try_parse_binary result")
        t.equal(parse_error.code, code, vector.name .. ": try_parse_binary code")
      end
    end)

    t.it("is consistent with the published JSON schema structure", function()
      local schema = read_json("spec/vectors/pikaid-v1.schema.json")

      t.equal(schema["$schema"], "https://json-schema.org/draft/2020-12/schema", "draft")
      t.equal(schema.type, "object", "schema type")

      for _, field in ipairs({ "meta", "valid", "invalid" }) do
        local found = false
        for _, required in ipairs(schema.required) do
          if required == field then
            found = true
          end
        end
        t.ok(found, "schema requires " .. field)
      end

      for _, vector in ipairs(vectors.valid) do
        t.ok(vector.id:match("^[0-9a-z]+$") ~= nil, vector.name .. ": id pattern")
        t.equal(#vector.id, 26, vector.name .. ": id width")
        t.equal(#vector.entropy_hex, 24, vector.name .. ": entropy hex width")
        t.equal(#vector.bin_hex, 34, vector.name .. ": binary hex width")
      end
    end)
  end)
end
