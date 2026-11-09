--- Pinned integrity checks for the vendored conformance data.
--
-- The digests below identify the exact bytes every other suite consumes. They
-- make an accidental fixture edit, a line-ending conversion, or a substitute
-- oracle visible before any conformance assertion runs.

local sha256 = require("spec.support.sha256")

local FIXTURES = {
  {
    path = "spec/vectors/pikaid-v1.json",
    digest = "b0c9dfdd063613424414fef5c9065fbd2f81d645d0ab42b34e27cde715613500",
  },
  {
    path = "spec/vectors/pikaid-v1.schema.json",
    digest = "4441d4dbaa6c5450ae9cbfb2438c53bc0421bba2b7fcc9ef9b158e5d1de0759e",
  },
  {
    path = "spec/fixtures/reference-cases.json",
    digest = "eaed34c145861ba3fa72f1f623b5167227a12348687436961008b1991ac580b7",
  },
}

return function(t)
  t.describe("vendored fixture integrity", function()
    t.it("matches the published SHA-256 test vectors", function()
      t.equal(
        sha256.hex(""),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "empty message"
      )
      t.equal(
        sha256.hex("abc"),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "abc message"
      )
      t.equal(
        sha256.hex(string.rep("a", 1000)),
        "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3",
        "1000 a characters"
      )
    end)

    t.it("pins every official and independent fixture byte-for-byte", function()
      for _, fixture in ipairs(FIXTURES) do
        local file = assert(io.open(fixture.path, "rb"), "cannot open " .. fixture.path)
        local bytes = file:read("*a")
        file:close()

        t.equal(sha256.hex(bytes), fixture.digest, fixture.path)
      end
    end)
  end)
end
