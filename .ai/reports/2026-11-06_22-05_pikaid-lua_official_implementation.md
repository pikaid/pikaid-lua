# pikaid-lua — Official Lua Implementation

## Summary

Implemented the official Lua implementation of **pikaid specification revision 1.0.4** in the verified repository `pikaid/pikaid-lua` (origin `https://github.com/pikaid/pikaid-lua.git`, branch `main`, base commit `f17d822`). The library is dependency-free pure Lua 5.3+ (5.3, 5.4 and 5.5 from PUC-Rio), split into three modules:

- `src/pikaid/init.lua` (498 lines) — public API, strict parsing, conversions, generation, typed errors, locale-independent comparison.
- `src/pikaid/base36.lua` (154 lines) — fixed-width Base36 timestamp codec and a six-limb 96-bit randomness codec that never requires a bignum or floating point.
- `src/pikaid/entropy.lua` (68 lines) — fail-closed `/dev/urandom` CSPRNG provider.

The deliverable also includes a zero-dependency conformance suite (57 tests, 10,418 assertions) driven by the unmodified official fixtures, an independent Python oracle (290 cases), hand-derived boundary known-answer tests, property/round-trip tests, entropy and clock failure tests, a LuaRocks rockspec, an MIT license, expanded documentation, and a GitHub Actions workflow. Local validation passes on all three supported Lua versions; total measured line coverage is 98.94%.

## Requirement Coverage

| Requirement | What was required | Status | Evidence |
| --- | --- | --- | --- |
| **REQ-1** | Exact textual format: 26 lowercase Base36 characters, 7 timestamp digits followed by 19 randomness digits (96 bits). | **PASS** | `base36.encode` emits exactly 7/19 digits with leading zeros; `pikaid.try_parse` enforces length 26 and `^[0-9a-z]+$`; official vectors, known answers and 290 oracle cases cover zero-padded and maximal values. |
| **REQ-2** | Exact binary format: 17 bytes, 5-byte unsigned big-endian timestamp in `0 .. 2^37-1` followed by 12 randomness bytes, equivalent to the text form. | **PASS** | `encode_binary_timestamp`/`decode_binary_timestamp` (`init.lua:90-109`); `try_parse_binary` rejects length ≠ 17 and timestamps above `MAX_TIMESTAMP`; all `bin_hex` fixtures round-trip. |
| **REQ-3** | Strict validation: no trimming, case folding, coercion or truncation; reject out-of-range timestamps and randomness ≥ 2^96 even when the shape is legal. | **PASS** | `try_parse`/`try_parse_binary` return typed errors for wrong type, length, alphabet, timestamp and randomness; `7oiylpimjg5u2ca1yps` (2^96) is rejected as `randomness_out_of_range`; `spec/validation_spec.lua`. |
| **REQ-4** | Lossless conversion between text, binary, timestamp and raw randomness fields, preserving leading zeros. | **PASS** | `to_binary`/`from_binary`/`timestamp`/`randomness`; round-trip property tests and 2,500-case ad hoc differential run (`from_binary`/`to_binary`/validity) on 5.3.6, 5.4.9 and 5.5.1. |
| **REQ-5** | Correct ordering semantics and honest caveats: chronological across distinct timestamps, random within one second, no monotonicity, one-second precision, locale dependence avoided. | **PASS** | `pikaid.compare` uses an explicit unsigned byte loop instead of locale-sensitive `<`; README "Ordering" section states the same-second randomness, non-monotonicity, one-second precision and database collation guidance; suite includes a non-ASCII collation test. |
| **REQ-6** | Real, documented public API (generation, validation, parsing, conversion, comparison, errors, constants). | **PASS** | `generate`, `generate_binary`, `new`, `validate`, `is_well_formed`, `validate_binary`, `parse`, `try_parse`, `parse_binary`, `try_parse_binary`, `to_binary`, `from_binary`, `timestamp`, `randomness`, `compare`, `is_error`, plus documented constants; README API tables match the code. |
| **REQ-7** | Substantive conformance tests: every official vector, independent known-answer tests, boundary cases, property tests, credible evidence — not circular or self-referential. | **PASS** | 57 tests / 10,418 assertions: all 4 valid + 6 invalid string + 4 invalid binary official vectors, official JSON Schema constraints, 290 independently generated Python arbitrary-precision cases (`reference-cases.json`), hand-derived Base36/boundary KATs, deterministic round-trip properties, entropy/clock failure modes, `math.random` independence, locale comparison. |
| **REQ-8** | Credible coverage of at least 90%, plus installable packaging and MIT-licensed documentation. | **PASS** | Coverage 98.94% total (`base36` 96.77%, `entropy` 100.00%, `init` 99.48%); `pikaid-0.1.0-1.rockspec` installs and imports on Lua 5.3/5.4/5.5; `LICENSE` (MIT); expanded `README.md` with format, API, errors, binary layout, ordering, security, platforms and development instructions. |
| **REQ-9** | GitHub Actions continuous integration and explicit scope/security limits. | **PASS** | `.github/workflows/ci.yml` runs the suite on ubuntu/macos × Lua 5.3.6/5.4.9/5.5.1, a lint+coverage job (90% gate) and a rockspec install job; README states identifiers are not secrets/tokens, uniqueness is probabilistic, timestamps are visible, `math.random` is never used and generation fails closed. Workflow execution itself is **NOT RUN** locally (no push performed) — see Deviations. |

## Root Cause or Technical Approach

The interesting engineering problem is that Lua integers are typically 64-bit while the randomness field is 96 bits, and plain Lua has no cryptographic RNG.

1. **96-bit arithmetic without bignums.** Randomness is held as six 16-bit limbs. Encoding performs long division by 36 from the most significant limb; every intermediate is at most `65535 + 35*65536 = 2,359,295 < 2^22`, so no overflow is possible on any 32-bit-or-wider Lua integer, and no float path is used. Decoding multiplies by 36 and adds a digit, least significant limb first, detecting overflow when a carry leaves the most significant limb. The 37-bit timestamp fits natively in a Lua integer, so the five-byte big-endian codec is a simple `% 256` / `// 256` loop.
2. **Strictness as a single pipeline.** `try_parse` checks type, then length, then the alphabet, then decodes the fields and maps a randomness overflow to `randomness_out_of_range`. `parse` raises the same error object that `try_parse` would return, so the raising and non-raising paths cannot diverge.
3. **Error objects instead of strings.** Failures are tables with `code`/`message` and a `__tostring` metamethod, raised with `error(obj, 0)`, so callers pattern-match on `code` without parsing text and the object is never rewritten by Lua's position prefix.
4. **Fail-closed randomness.** `pikaid.entropy` reads exactly 12 bytes from `/dev/urandom` with binary I/O and raises on open failure, read failure or short read. `pikaid.new({ entropy = ..., clock = ... })` injects verified providers for tests, sandboxes and platforms without the device; the provider result is checked for type and exact length, and there is no fallback to `math.random` anywhere.
5. **Honest ordering.** `compare` performs an unsigned byte loop because Lua's `<` uses the process locale; the documentation promises chronological ordering only across different timestamps.
6. **Independent test oracle.** Expected values come from three mutually independent sources: the unmodified official PHP interoperability fixtures, a Python arbitrary-precision generator (`spec/tools/generate_reference_cases.py`, 290 deterministic cases) and hand-computed anchors/boundaries, so the suite is not validating the implementation against itself. Test support (JSON reader, hex decoder, harness) is intentionally minimal and dependency-free.

## Files Changed

Added (untracked in git):

- `src/pikaid/init.lua` (498 lines) — public API and conversions.
- `src/pikaid/base36.lua` (154 lines) — Base36 and 96-bit limb codecs.
- `src/pikaid/entropy.lua` (68 lines) — OS CSPRNG provider.
- `spec/run.lua`, `spec/{vectors,reference,known_answers,validation,conversion,generation,api}_spec.lua` — conformance suite.
- `spec/support/{harness,json,hex}.lua` — zero-dependency test support.
- `spec/fixtures/reference-cases.json` — 290 independent oracle cases.
- `spec/tools/generate_reference_cases.py` — deterministic oracle generator (128 lines).
- `spec/vectors/{pikaid-v1.json,pikaid-v1.schema.json,README.md}` — unmodified official fixtures plus provenance/hashes.
- `pikaid-0.1.0-1.rockspec` — LuaRocks packaging (modules, `lua >= 5.3, < 5.6`).
- `LICENSE` — MIT, matching sibling official implementations.
- `.github/workflows/ci.yml` — test matrix, lint/coverage gate, packaging job.
- `.gitignore`, `.luacheckrc`, `.luacov` — repository hygiene and tool configuration.

Modified:

- `README.md` — expanded from the reserved-repository stub into full documentation; the pikaid logo header and branding were preserved verbatim.

Untouched: `opencode.jsonc`; the pre-existing `.DS_Store` (now covered by `.gitignore`) was neither deleted nor committed.

## Validation

| Check | Result | Command / evidence |
| --- | --- | --- |
| Repository identity | **PASS** | `git remote get-url origin` → `https://github.com/pikaid/pikaid-lua.git`; branch `main`; base commit `f17d822`. |
| Suite on Lua 5.3.6 | **PASS** | `lua spec/run.lua` → `57 tests, 10418 assertions: 57 passed, 0 failed`. |
| Suite on Lua 5.4.9 | **PASS** | Same command → `57 tests, 10418 assertions: 57 passed, 0 failed`. |
| Suite on Lua 5.5.1 | **PASS** | Same command → `57 tests, 10418 assertions: 57 passed, 0 failed`. |
| Lint | **PASS** | `luacheck src spec` (luacheck 1.2.0, Lua 5.4) → `Total: 0 warnings / 0 errors in 14 files`. |
| Coverage | **PASS** | `LUA_PATH='./src/?.lua;./src/?/init.lua;;' lua -lluacov spec/run.lua && luacov` → `base36.lua 60/62 (96.77%)`, `entropy.lua 30/30 (100.00%)`, `init.lua 190/191 (99.48%)`, `Total 280/283 (98.94%)`; gate is 90%. The 3 missed lines are defensive `nil`/`invalid_character` returns unreachable behind the preceding alphabet check. |
| Official vectors | **PASS** | Unmodified `pikaid-v1.json`: 4 valid, 6 invalid string, 4 invalid binary cases all agree; JSON Schema constraints asserted. SHA-256 `b0c9dfdd…613500` (vectors) and `4441d4db…1de0759e` (schema). |
| Independent oracle | **PASS** | 290 cases from `reference-cases.json` (SHA-256 `eaed34c1…1ac580b7`) pass; re-running `python3 spec/tools/generate_reference_cases.py` reproduced the identical file hash, proving determinism. |
| Known answers / boundaries | **PASS** | Anchors `00000000000000000000000000`, `zzzzzzz7oiylpimjg5u2ca1ypr`, `0s44we8002loz3po6mcf6vsn23`, `00000010000000000000000001`; timestamp max `78364164095` and max+1 rejection; randomness `2^96-1` accepted, `2^96` rejected; leading-zero entropy preserved. |
| Round-trip properties | **PASS** | Deterministic text↔binary round trips inside the suite; ad hoc differential run of 2,500 generated `(timestamp, 96-bit entropy)` pairs through `from_binary`/`to_binary`/`validate` on 5.3.6, 5.4.9 and 5.5.1 — all passed. The ad hoc fixture is scratch and not committed. |
| Entropy/clock failure modes | **PASS** | Device unreadable (`/dev/null`), device missing, short read, non-string/short provider output, provider raising, clock raising, float and out-of-range clock all produce the documented errors; `math.random` is never called. |
| Packaging | **PASS** | `luarocks --lua-version=<V> --lua-dir=<D> --tree=<tmp> make pikaid-0.1.0-1.rockspec` for Lua 5.3/5.4/5.5 → installed; `package.searchpath` confirmed import from the installed tree; generate/validate/round-trip/error smoke test passed on all three. |
| CI configuration | **PASS (static)** | `ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml")'` → parses; local replication of its build step (`make posix` for Lua 5.5.1) and full suite passed on macOS. |
| CI workflow execution | **NOT RUN** | No push was performed, so GitHub Actions never executed; matrix/action behaviour on hosted runners is unverified locally. |
| Independent subagent review | **NOT RUN** | `review-critical` failed with `Model unavailable: profile/large` and `review` with `Model unavailable: profile/small`. Coverage was replaced by a line-by-line self-audit of `base36.lua`, `init.lua` and `entropy.lua`; no defect was found. |
| Git commit / push / release / registry publish | **NOT RUN** | Deliberately out of scope (no commit requested, no release/tag, no publishing). All new files remain untracked; `README.md` is modified but not committed. |

## Deviations and Unresolved Issues

1. **Nothing is committed or pushed.** The working tree contains the complete implementation as untracked files plus a modified `README.md`. No tag, release, LuaRocks publication or force-push was performed.
2. **Rockspec source points at `main`.** Because no `v0.1.0` tag exists, `source` uses `branch = "main"` so `luarocks make` works from a checkout today; this should be replaced by a tag URL when a release is cut.
3. **Independent review was not possible.** Both review subagents were unavailable due to missing model profiles, so the quality evidence is the conformance suite, coverage, lint, ad hoc differential testing and a manual self-audit rather than an independent high-risk review.
4. **Coverage is 98.94%, not 100%.** The three missed lines are unreachable defensive checks guarded by earlier alphabet validation; they were left in place rather than deleted or artificially exercised.
5. **GitHub Actions has not actually run.** The workflow is validated only by YAML parsing and by locally reproducing its commands; hosted-runner behaviour (action versions, `make posix` on ubuntu, `awk` coverage gate) remains unverified until the branch is pushed.
6. **Windows has no default entropy provider.** By design the library fails closed there; callers must inject a verified CSPRNG through `pikaid.new`. This is documented in the README platform table.
7. **The 2,500-case differential fuzz run is not committed.** It was ad hoc scratch validation; the committed oracle fixture contains the 290 deterministic cases.
8. **Minor:** `base36.encode_randomness` hardcodes the 19-digit width (matching the immutable spec constant) instead of taking the width as a parameter; `init.lua` keeps a local `BINARY_TIMESTAMP_BYTES = 5` that mirrors the format. Neither is a correctness risk.

No blocking issue or unmet mandatory requirement remains.

## Final Status

task_result: PASS
