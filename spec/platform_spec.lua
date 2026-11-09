--- Platform capability checks.
--
-- pikaid can only represent its 7-digit timestamp on an interpreter with at
-- least 36^7 - 1 available in an integer. A `LUA_32BITS` build is refused when
-- `pikaid.base36` loads. The refusal is reproduced here by lowering
-- `math.maxinteger` while the module chunk runs, so the guard is exercised on
-- the ordinary 64-bit interpreters used for development and CI as well.

local BASE36_PATH = "src/pikaid/base36.lua"

local function load_base36_with_maxinteger(limit)
  local chunk, load_error = loadfile(BASE36_PATH)
  assert(chunk, load_error)

  -- `math.maxinteger` is documented as read-only, so it is written through
  -- rawset; the interpreter itself reads it from the table at run time.
  local original = math.maxinteger
  rawset(math, "maxinteger", limit)

  local ok, result = pcall(chunk)
  rawset(math, "maxinteger", original)

  return ok, result
end

return function(t)
  t.describe("platform capabilities", function()
    t.it("reports the interpreter's integer width", function()
      t.ok(math.maxinteger > 2 ^ 53, "development requires a 64-bit integer build")
      t.ok(math.maxinteger >= 78364164095, "timestamp range fits")
    end)

    t.it("refuses to load with 32-bit integers", function()
      local ok, message = load_base36_with_maxinteger(2147483647)

      t.equal(ok, false, "32-bit load must fail")
      t.ok(tostring(message):find("64-bit integers", 1, true) ~= nil, "message names the requirement")
      t.ok(tostring(message):find("32-bit", 1, true) ~= nil, "message names the cause")
    end)

    t.it("loads normally with 64-bit integers", function()
      local ok, message = load_base36_with_maxinteger(math.maxinteger)

      t.equal(ok, true, "64-bit load succeeds: " .. tostring(message))
    end)
  end)
end
