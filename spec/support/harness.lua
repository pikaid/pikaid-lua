--- Small zero-dependency test harness for the pikaid test suite.
--
-- The suite is plain Lua so it runs identically on every supported Lua version
-- without a package manager or a test framework dependency.

local harness = {}

harness.tests = 0
harness.assertions = 0
harness.failures = {}

local function display(value)
  if type(value) == "string" then
    return string.format("%q (length %d)", value, #value)
  end

  return tostring(value)
end

local function current_group(name)
  if harness.group then
    return harness.group .. " / " .. name
  end

  return name
end

--- Group related tests. A failing group body is reported as one failure.
--
-- @tparam string name group name
-- @tparam function body test body
function harness.describe(name, body)
  local previous = harness.group
  harness.group = current_group(name)
  harness.tests = harness.tests + 1

  local ok, message = pcall(body)

  if not ok then
    harness.failures[#harness.failures + 1] = {
      group = harness.group,
      name = "<group body>",
      message = tostring(message),
    }
  end

  harness.group = previous
end

--- Register and run one test.
--
-- @tparam string name test name
-- @tparam function body test body
function harness.it(name, body)
  harness.tests = harness.tests + 1

  local ok, message = pcall(body)

  if not ok then
    harness.failures[#harness.failures + 1] = {
      group = harness.group or "(root)",
      name = name,
      message = tostring(message),
    }
  end
end

--- Assert that two values are equal.
--
-- @param actual observed value
-- @param expected expected value
-- @tparam[opt] string label failure label
function harness.equal(actual, expected, label)
  harness.assertions = harness.assertions + 1

  if actual ~= expected then
    error(string.format(
      "%s: expected %s, got %s",
      label or "equal",
      display(expected),
      display(actual)
    ), 0)
  end
end

--- Assert that a value is truthy.
--
-- @param value observed value
-- @tparam[opt] string label failure label
function harness.ok(value, label)
  harness.assertions = harness.assertions + 1

  if not value then
    error((label or "ok") .. ": expected a truthy value", 0)
  end
end

--- Assert that a value is false or nil.
--
-- @param value observed value
-- @tparam[opt] string label failure label
function harness.not_ok(value, label)
  harness.assertions = harness.assertions + 1

  if value then
    error((label or "not_ok") .. ": expected a false value, got " .. display(value), 0)
  end
end

--- Assert that a function raises, and return the raised value.
--
-- @tparam function body callable under test
-- @tparam[opt] string label failure label
-- @return the raised value
function harness.raises(body, label)
  harness.assertions = harness.assertions + 1

  local ok, raised = pcall(body)

  if ok then
    error((label or "raises") .. ": expected an error, but the call succeeded", 0)
  end

  return raised
end

--- Assert that a function raises a pikaid error with a specific code.
--
-- @tparam string code expected error code
-- @tparam function body callable under test
-- @tparam[opt] string label failure label
-- @return the raised error object
function harness.error_code(code, body, label)
  local raised = harness.raises(body, label)

  if type(raised) ~= "table" or raised.code ~= code then
    error(string.format(
      "%s: expected error code %q, got %s",
      label or "error_code",
      code,
      tostring(raised)
    ), 0)
  end

  return raised
end

--- Print failures and the summary, and return whether the suite passed.
--
-- @treturn boolean whether every test passed
function harness.finish()
  for _, failure in ipairs(harness.failures) do
    io.stderr:write(string.format(
      "FAIL %s :: %s\n  %s\n",
      failure.group,
      failure.name,
      failure.message
    ))
  end

  local failed = #harness.failures
  local passed = harness.tests - failed

  io.write(string.format(
    "\n%d tests, %d assertions: %d passed, %d failed\n",
    harness.tests,
    harness.assertions,
    passed,
    failed
  ))

  return failed == 0
end

return harness
