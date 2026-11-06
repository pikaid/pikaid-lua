<p align="center">
  <img src="https://raw.githubusercontent.com/pikaid/pikaid-specs/v1.0.4/logo.png" alt="pikaid" width="300" />
</p>

<p align="center">
  <strong>Small · Sortable · Secure ID generator</strong>
</p>

# pikaid — Official Lua Implementation

**Status: complete against specification 1.0.4 — not yet released to LuaRocks.**

This repository contains the **official Lua implementation** of [pikaid](https://github.com/pikaid), a compact, chronologically sortable, collision-resistant identifier format for databases, APIs, and distributed systems.

The pikaid identifier format is immutable and unversioned: **26 lowercase Base36 characters** with a **17-byte binary representation**.

## Canonical specification

The authoritative definition is [pikaid specification revision 1.0.4](https://github.com/pikaid/pikaid-specs/tree/v1.0.4).

This implementation targets that revision exactly. It does not extend the format, and it does not invent a version prefix, checksum, or alternate alphabet.

## Features

- **Exact format.** 26 lowercase Base36 characters: 7 timestamp digits and 19 randomness digits carrying 96 bits.
- **Lossless binary form.** 17 bytes: 5 unsigned big-endian timestamp bytes and the 12 randomness bytes unchanged.
- **Strict validation.** No trimming, case folding, truncation, or silent coercion; malformed input is rejected with a typed error.
- **Cryptographic generation.** Randomness comes from the operating system CSPRNG, never from `math.random`.
- **Fail-closed.** If entropy or the clock is unavailable, generation raises instead of returning a weaker identifier.
- **Injectable providers.** Supply your own verified CSPRNG and clock for tests, sandboxes, or unsupported platforms.
- **Locale-independent comparison.** Ordering uses unsigned byte comparison rather than Lua's locale-sensitive `<`.
- **No dependencies.** Pure Lua 5.3+, using only the standard library.

## Requirements

- **Lua 5.3, 5.4, or 5.5** from PUC-Rio. The implementation needs the integer subtype, the `//` operator, and `math.type`. It does **not** support Lua 5.1, Lua 5.2, or LuaJIT.
- On Linux, macOS, and the BSDs, a readable `/dev/urandom`.
- On other platforms, including Windows, a verified entropy provider passed to `pikaid.new`.

## Installation

The library is not published to LuaRocks yet, so install from a checkout:

```sh
git clone https://github.com/pikaid/pikaid-lua.git
cd pikaid-lua
luarocks make pikaid-0.1.0-1.rockspec
```

Without LuaRocks, put `src/` on `package.path`:

```sh
LUA_PATH='./src/?.lua;./src/?/init.lua;;' lua your_script.lua
```

## Quick start

```lua
local pikaid = require("pikaid")

local id = pikaid.generate()
-- "0s44we8002loz3po6mcf6vsn23"

pikaid.validate(id)            --> true
pikaid.is_well_formed(id)      --> true
pikaid.timestamp(id)           --> 1700000000
pikaid.randomness(id)          --> 12 raw bytes

local parsed = pikaid.parse(id)
-- { timestamp = 1700000000,
--   randomness = <12 raw bytes, hex 00112233445566778899aabb>,
--   randomness_hex = "00112233445566778899aabb" }

local binary = pikaid.to_binary(id)      -- exactly 17 bytes
local restored = pikaid.from_binary(binary)
assert(restored == id)

local ok, err = pikaid.try_parse("not a pikaid")
-- ok  == nil
-- err == { code = "invalid_length", message = "..." }
print(tostring(err))  --> "pikaid: invalid_length: ..."
```

## API

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
| `pikaid.VERSION` | `"0.1.0"` |
| `pikaid.STRING_LENGTH` | `26` |
| `pikaid.BINARY_LENGTH` | `17` |
| `pikaid.TIMESTAMP_DIGITS` | `7` |
| `pikaid.RANDOMNESS_DIGITS` | `19` |
| `pikaid.ENTROPY_BYTES` | `12` |
| `pikaid.MAX_TIMESTAMP` | `78364164095` (`36^7 - 1`, 4453-04-05T15:21:35Z) |

`pikaid.VERSION` is the library version; the identifier format itself is unversioned.

## Binary representation

| Offset | Length | Contents |
| --- | --- | --- |
| `0` | 5 | timestamp, unsigned big-endian, `0 .. 2^37 - 1` |
| `5` | 12 | randomness bytes, unchanged |

The text and binary forms are lossless translations of each other. Leading zeroes are always preserved.

## Ordering

Valid identifiers with different timestamps sort chronologically in both forms, because the timestamp occupies the most significant digits and the most significant bytes.

Two identifiers created within the same second have a random relative order. **Generation within a second is not monotonic**, and pikaid does not promise that a later call returns a greater identifier.

`pikaid.compare` compares raw unsigned bytes and is independent of the process locale. Lua's `<` operator is not: it follows the collation set by `os.setlocale`, so sorting pikaid values with `<` in a non-ASCII locale such as Turkish can reorder them. Use `pikaid.compare`, or store the binary form in a `BINARY`/`BLOB` column.

When storing text identifiers in a database, use an ASCII-compatible collation. A case-insensitive or language-aware collation can change the ordering of the Base36 alphabet.

## Security notes

pikaid identifiers are **identifiers**, not secrets:

- 96 bits of randomness make accidental collisions negligible, but uniqueness remains probabilistic. Nothing in the format guarantees that two independently generated identifiers differ.
- Identifiers are not authentication tokens, session keys, passwords, or capability grants. They are not encrypted and carry no signature; the timestamp is readable by anyone.
- Randomness is unpredictable only when the entropy provider is cryptographic. `math.random` is not, and this library never uses it. The built-in provider reads `/dev/urandom`; on platforms without it, generation fails instead of degrading.
- The timestamp leaks the creation second. Do not generate identifiers for data whose creation time is sensitive.
- Timestamps come from the wall clock, which can move backwards. Identifiers remain valid; their order simply reflects the clock value that was recorded.

## Platform support

| Platform | Default entropy source | Notes |
| --- | --- | --- |
| Linux | `/dev/urandom` | supported |
| macOS | `/dev/urandom` | supported |
| BSD | `/dev/urandom` | supported |
| Windows | none | supply `options.entropy`; generation fails closed otherwise |

## Development

Run the conformance suite:

```sh
lua spec/run.lua
```

Lint and coverage:

```sh
luacheck src spec
LUA_PATH='./src/?.lua;./src/?/init.lua;;' lua -lluacov spec/run.lua && luacov
```

The suite is dependency-free and runs on every supported Lua version. It covers:

- every case in the official `pikaid-v1.json` fixture set, unmodified;
- the official JSON Schema's constraints, as executable assertions;
- 290 cases from an independent Python arbitrary-precision oracle (`spec/fixtures/reference-cases.json`, generated by `spec/tools/generate_reference_cases.py`);
- hand-derived known answers for the Base36 anchors and both overflow boundaries;
- strict rejection of wrong types, lengths, characters, and out-of-range fields;
- lossless round-trips over deterministic property cases;
- entropy-provider and clock failure modes, including the guarantee that `math.random` is never consulted;
- locale-independent comparison under a non-ASCII collation when the platform provides one.

Continuous integration runs the same suite on Linux and macOS against Lua 5.3, 5.4, and 5.5, together with linting and a coverage gate.

## Interoperability

`spec/vectors/pikaid-v1.json` and `spec/vectors/pikaid-v1.schema.json` are copied unmodified from pikaid specification 1.0.4 at commit `17014d76f568c3ac9f9ce2927c1a018fdbc36d1d`; their provenance and hashes are recorded in `spec/vectors/README.md`. The PHP implementation's published fixtures are treated only as independent interoperability data, never as the normative source.

## License

[MIT](LICENSE) © 2026 larananas (Lara G.)
