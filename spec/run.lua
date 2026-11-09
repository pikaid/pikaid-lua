--- Test runner for the pikaid Lua implementation.
--
-- Run from the repository root:
--
--     lua spec/run.lua
--
-- The exit status is zero only when every test passes.

package.path = table.concat({
  "./src/?.lua",
  "./src/?/init.lua",
  "./?.lua",
  "./?/init.lua",
  package.path,
}, ";")

local harness = require("spec.support.harness")

local suites = {
  "spec.fixture_digests_spec",
  "spec.vectors_spec",
  "spec.reference_spec",
  "spec.known_answers_spec",
  "spec.validation_spec",
  "spec.conversion_spec",
  "spec.generation_spec",
  "spec.platform_spec",
  "spec.api_spec",
  "spec.readme_spec",
}

for _, name in ipairs(suites) do
  local suite = require(name)
  suite(harness)
end

os.exit(harness.finish() and 0 or 1)
