<p align="center">
  <a href="https://github.com/pikaid/pikaid-specs">
    <img src="https://raw.githubusercontent.com/pikaid/pikaid-specs/v1.0.4/logo.png" alt="pikaid" width="300">
  </a>
</p>

<p align="center">
  <strong>Small · Sortable · Secure ID generator</strong>
</p>

<div align="center">

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Lua](https://img.shields.io/badge/language-Lua-2C2D72.svg)](https://github.com/pikaid/pikaid-lua)
[![CI](https://github.com/pikaid/pikaid-lua/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/pikaid/pikaid-lua/actions/workflows/ci.yml)
[![Official implementation](https://img.shields.io/badge/official-implementation-2e7d32.svg)](https://github.com/pikaid/pikaid-specs)
[![Specification 1.0.4](https://img.shields.io/badge/spec-1.0.4-4b56a6.svg)](https://github.com/pikaid/pikaid-specs/tree/v1.0.4)

</div>

**pikaid** is the **official Lua implementation** of a compact, chronologically sortable, collision-resistant identifier format for databases, APIs, and distributed systems.

This is the immutable, unversioned [pikaid format](https://github.com/pikaid/pikaid-specs/tree/v1.0.4), documented in specification revision **1.0.4**.

## ✨ Why pikaid?

- **Short:** Compact, readable IDs for URLs, logs, and API resources.
- **Sortable:** Lexicographically ordered by timestamp, with **one-second precision**.
- **Collision-resistant:** 96 bits of cryptographic randomness make collisions extremely unlikely, never impossible.
- **Storage-friendly:** Use `BINARY(17)` or readable `CHAR(26)`.
- **Distributed-friendly:** No central sequence generator or coordination required.

## 🧬 Identifier format

A pikaid contains **26 lowercase Base36 characters**: a **7-character Unix-seconds timestamp** followed by **19 characters encoding 96 bits of cryptographic randomness**. Its binary form is **17 bytes**: 5 unsigned big-endian timestamp bytes followed by 12 randomness bytes.

![Identifier structure](https://raw.githubusercontent.com/pikaid/pikaid-specs/v1.0.4/structure.svg)

> **Ordering:** Different seconds sort chronologically. Within the same second, randomness—not issuance order—decides the order.

> **Security:** These are identifiers, **not secrets**, session credentials, authentication tokens, or API keys.

## ⚙️ Requirements

- **Lua 5.3, 5.4, or 5.5** from PUC-Rio. The implementation needs the integer subtype, the `//` operator, and `math.type`. It does **not** support Lua 5.1, Lua 5.2, or LuaJIT.
- A standard 64-bit-integer build. The timestamp range exceeds 32-bit integers, so a `LUA_32BITS` interpreter is rejected when the module loads instead of silently producing corrupt identifiers.
- On Linux and macOS, a readable `/dev/urandom`. The same device path is used on the BSDs, where it has the same semantics, but CI does not run on BSD.
- On other platforms, including Windows, a verified entropy provider passed to `pikaid.new`. Generation fails closed rather than falling back to a weaker source.

## 📦 Installation

The library is not published to LuaRocks yet, so install from a checkout:

```sh
git clone https://github.com/pikaid/pikaid-lua.git
cd pikaid-lua
luarocks make pikaid-1.0.0-1.rockspec
```

Without LuaRocks, put `src/` on `package.path`:

```sh
LUA_PATH='./src/?.lua;./src/?/init.lua;;' lua your_script.lua
```

Save the quick start below as `demo.lua`, then run `lua demo.lua` after installation.

## 🚀 Basic Usage

```lua
local pikaid = require("pikaid")

local id = pikaid.generate()
assert(pikaid.validate(id))
assert(pikaid.is_well_formed(id))
local binary = pikaid.to_binary(id)
assert(#binary == 17)
assert(pikaid.from_binary(binary) == id)
print(id, pikaid.timestamp(id))
```

The identifier varies on every call; the timestamp is the current Unix second.

## 💡 Example Use Case

Use pikaid to identify **users, orders, invoices, uploads, events, and API resources**. Independent services can generate compact IDs without a shared counter, while timestamp-based ordering helps with indexing, sorting, and logs.

## 📚 Canonical specification

- [Canonical specification](https://github.com/pikaid/pikaid-specs)
- [Revision 1.0.4](https://github.com/pikaid/pikaid-specs/tree/v1.0.4)

Specification revisions describe the format; they do not change the encoded identifiers.

## 🧩 API Reference

### Generation

| Function | Result |
| --- | --- |
| `pikaid.generate([timestamp])` | 26-character identifier |
| `pikaid.generate_binary([timestamp])` | 17-byte identifier |
| `pikaid.new([options])` | instance exposing `:generate([timestamp])` and `:generate_binary([timestamp])` |

`timestamp` is optional. When omitted, the current Unix time in whole seconds is used. Supply it only when you already know the correct second.

Because plain Lua exposes no cryptographic random generator, instances are configurable:

```lua
local ids = pikaid.new({
  entropy = function(byte_count) return my_verified_csprng(byte_count) end,
  clock = function() return my_clock_seconds() end,
})
```

An entropy provider must return exactly 12 bytes; anything else fails closed with `entropy_unavailable`. A clock must return an integer number of seconds inside the supported range.

### Validation

| Function | Result |
| --- | --- |
| `pikaid.validate(value)` | `true` only for a fully valid string |
| `pikaid.is_well_formed(value)` | `true` when the value has the 26-character lowercase Base36 shape |
| `pikaid.validate_binary(value)` | `true` only for a fully valid 17-byte value |

`is_well_formed` is a shape check, not a validity check: a string can have the right shape while its randomness exceeds 96 bits, in which case `validate` is `false`.

### Parsing and conversion

| Function | Result |
| --- | --- |
| `pikaid.parse(value)` | `{ timestamp, randomness, randomness_hex }` or raises |
| `pikaid.try_parse(value)` | the same table, or `nil, error_object` |
| `pikaid.parse_binary(value)` | parsed fields from a binary value, or raises |
| `pikaid.try_parse_binary(value)` | the same table, or `nil, error_object` |
| `pikaid.to_binary(value)` | 17-byte binary form |
| `pikaid.from_binary(value)` | canonical 26-character form |
| `pikaid.timestamp(value)` | integer Unix seconds |
| `pikaid.randomness(value)` | 12 raw bytes |

### Comparison and errors

| Function | Result |
| --- | --- |
| `pikaid.compare(left, right)` | `-1`, `0`, or `1` by unsigned byte order |
| `pikaid.is_error(value)` | `true` for a pikaid error object |

Functions without a `try_` prefix raise on invalid input. The raised value is a table with `code` and `message` fields and a `__tostring` metamethod that renders as `pikaid: <code>: <message>`; `error` is called with level `0`, so the object arrives unchanged.

Error codes:

| Code | Meaning |
| --- | --- |
| `invalid_type` | operand is not a string, or an option has the wrong type |
| `invalid_length` | wrong number of characters or bytes |
| `invalid_character` | a character outside `0-9a-z` |
| `invalid_timestamp` | timestamp supplied or returned by a clock is not an integer |
| `timestamp_out_of_range` | timestamp outside `0 .. 78364164095` |
| `randomness_out_of_range` | randomness is at least 2^96 |
| `entropy_unavailable` | the entropy provider failed or returned the wrong length |
| `clock_unavailable` | the clock raised |

### Constants

| Constant | Value |
| --- | --- |
| `pikaid.VERSION` | `"1.0.0"` |
| `pikaid.STRING_LENGTH` | `26` |
| `pikaid.BINARY_LENGTH` | `17` |
| `pikaid.TIMESTAMP_DIGITS` | `7` |
| `pikaid.RANDOMNESS_DIGITS` | `19` |
| `pikaid.ENTROPY_BYTES` | `12` |
| `pikaid.MAX_TIMESTAMP` | `78364164095` (`36^7 - 1`, 4453-04-05T15:21:35Z) |

`pikaid.VERSION` is the library version; the identifier format itself is unversioned.

## 🔄 Order Guarantee

Valid identifiers with different timestamps sort chronologically in both forms, because the timestamp occupies the most significant digits and the most significant bytes.

Two identifiers created within the same second have a random relative order. **Generation within a second is not monotonic**, and pikaid does not promise that a later call returns a greater identifier.

`pikaid.compare` compares raw unsigned bytes and is independent of the process locale. Lua's `<` operator is not: it follows the collation set by `os.setlocale`, so sorting pikaid values with `<` in a non-ASCII locale such as Turkish can reorder them. Use `pikaid.compare`, or store the binary form in a `BINARY`/`BLOB` column.

When storing text identifiers in a database, use an ASCII-compatible collation. A case-insensitive or language-aware collation can change the ordering of the Base36 alphabet.

## 🛢 Storage Recommendations

| Representation | Size | Recommended for |
| --- | ---: | --- |
| **BINARY(17)** | 17 bytes | Compact primary keys and indexes |
| **CHAR(26)** | 26 characters | Readable SQL, debugging, URLs, and logs |

Use an **ASCII bytewise/binary collation** for text columns (for example, `ascii_bin` on MariaDB/MySQL). Case-insensitive or locale-aware sorting is not a substitute for canonical bytewise comparison.

## ✅ Verification and release status

The [CI workflow](https://github.com/pikaid/pikaid-lua/actions/workflows/ci.yml) runs native tests, pinned automated conformance checks, and language-specific quality gates. To run the native checks locally from a checkout, use `lua spec/run.lua`.

**Automated passing tests are not a security certification.** The independent CSPRNG source and failure-path audits (`P-GENERATE-RNG-SOURCE` and `P-GENERATE-RNG-FAILURE`) still require separate human evidence.

<details>
<summary>Platform, tooling, and conformance details</summary>

| Platform | Default entropy source | Notes |
| --- | --- | --- |
| Linux | `/dev/urandom` | supported; exercised by CI |
| macOS | `/dev/urandom` | supported; exercised by CI |
| BSD | `/dev/urandom` | expected to work by the same device contract; not exercised by CI |
| Windows | none | supply `options.entropy`; generation fails closed otherwise; not exercised by CI |

Run the conformance suite:

```sh
lua spec/run.lua
```

Lint and coverage:

```sh
luacheck src spec
eval "$(luarocks path)"
LUA_PATH="./src/?.lua;./src/?/init.lua;${LUA_PATH:-}" lua -lluacov spec/run.lua && luacov
```

The suite is dependency-free and runs on every supported Lua version. It covers:

- every case in the official `pikaid-v1.json` fixture set, unmodified, with its SHA-256 digest pinned;
- the official JSON Schema's constraints, as executable assertions;
- 290 cases from an independent Python arbitrary-precision oracle (`spec/fixtures/reference-cases.json`, generated by `spec/tools/generate_reference_cases.py`), for parsing, conversion, and generation;
- hand-derived known answers for the Base36 anchors and both overflow boundaries;
- strict rejection of wrong types, lengths, characters (including CR, LF, CRLF, and multi-byte zero-width characters), and out-of-range fields;
- lossless round-trips over deterministic property cases;
- entropy-provider and clock failure modes, including the guarantee that `math.random` is never consulted;
- locale-independent comparison under a non-ASCII collation when the platform provides one;
- the documented README quick start, run against both a checkout and an installed package.

### Official conformance suite

`spec/tools/jsonl_adapter.lua` is a test-only JSON-Lines bridge that the shared
`pikaid-specs` runner drives. It contains no codec, validator, or generator of
its own: every semantic operation is delegated to the real public `pikaid`
module, and it advertises only capabilities that a public function backs.

```sh
repo="$PWD"
spec_sha=059780cc0e5b113443812720d95c630649bf3aa3
spec_dir="${TMPDIR:-/tmp}/pikaid-specs"
rm -rf "$spec_dir"
git clone https://github.com/pikaid/pikaid-specs.git "$spec_dir"
git -C "$spec_dir" checkout "$spec_sha"
python3 -m pip install jsonschema==4.26.0
(cd "$spec_dir/conformance" && \
  python3 tools/run_adapter.py --automated-only -- \
    lua "$repo/spec/tools/jsonl_adapter.lua")
```

`--automated-only` exits `0` only when every automated check passes. It still
leaves the suite's manual security audits outstanding, so it is not a
conformance certification.

Continuous integration runs the same suite on Linux and macOS against Lua 5.3, 5.4, and 5.5. A separate job checks out the official `pikaid-specs` suite at the pinned commit above, verifies its fixture digests, runs its verifier tests and independent Node oracle, and drives the JSONL adapter with `--automated-only`. Further jobs run `luacheck`, regenerate the independent oracle and fail on any diff, enforce a line-coverage gate, build a `LUA_32BITS` interpreter and assert that `pikaid` refuses to load on it, lint and install the rockspec, and check that the source archive excludes local artifacts. All workflows use read-only repository permissions.

The Windows and BSD default entropy paths are not exercised by CI: Windows has no `/dev/urandom`, so Windows callers must inject a verified provider, while BSD is expected to work through the same `/dev/urandom` contract as Linux and macOS. The generation logic itself is platform-independent, and a missing or failing provider always raises instead of degrading.

- [RELEASING.md](RELEASING.md) — non-destructive tag, build and publish runbook.
- [`docs/csprng-review-packet.md`](https://github.com/pikaid/pikaid-lua/blob/main/docs/csprng-review-packet.md)
  — file/line map for the two manual CSPRNG audits
  (`P-GENERATE-RNG-SOURCE`, `P-GENERATE-RNG-FAILURE`). Automated conformance
  does not substitute for the independent human review.

`spec/vectors/pikaid-v1.json` and `spec/vectors/pikaid-v1.schema.json` are copied unmodified from the pikaid-php `v1.2.0` release at commit `e3f843edeb5157a5d2d25196cac0d69580810a95`; their provenance and hashes are recorded in `spec/vectors/README.md`. They implement the rules of pikaid specification revision `1.0.4` (commit `17014d76f568c3ac9f9ce2927c1a018fdbc36d1d`), which remains the normative source. The PHP fixtures are interoperability data, not the normative definition.

</details>

Registry publication is not implied by a green CI: use the installation method documented above.

## 🤝 Contributing

Contributions are always welcome! 💙

Whether you're fixing a typo, improving documentation, adding tests, or making pikaid even better, every contribution is appreciated.

**Want to help? Here's how:**

- 🐛 **Found a bug?** [Open an issue](https://github.com/pikaid/pikaid-lua/issues) with clear reproduction steps.
- 💡 **Have an idea?** Start with an issue before making major changes.
- 🛠️ **Ready to contribute?** Open a pull request explaining your changes.
- 🧪 **Keep it tested.** Add meaningful regression tests for behavior changes and follow the existing conventions.
- ✅ **Make sure CI passes.** All required checks must be green before a pull request is merged. No shortcuts!

**One important rule:** pikaid's identifier format is immutable. Contributions must preserve the [canonical specification (revision 1.0.4)](https://github.com/pikaid/pikaid-specs/tree/v1.0.4).

🔐 **Found a security vulnerability?** Report it privately using GitHub's security reporting (when available), or [contact the maintainer](mailto:larananas.dev@proton.me)—not through a public issue.

**Every improvement matters, big or small. Thanks for helping make pikaid better!** 🐇

## 📄 License

The implementation is available under the [MIT License](LICENSE).

## ✉️ Contact

For licensing or project-related questions: [larananas.dev@proton.me](mailto:larananas.dev@proton.me).

