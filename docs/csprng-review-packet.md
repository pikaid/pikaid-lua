# CSPRNG review packet — pikaid-lua

**Purpose:** give an independent human reviewer everything needed to audit the
two manual official-suite obligations, `P-GENERATE-RNG-SOURCE` and
`P-GENERATE-RNG-FAILURE`, without reading the whole library.

**Status: NOT REVIEWED.** No human review has been performed. The automated
suite deliberately leaves both audits outstanding, and this packet does not
claim otherwise. Generating identifiers is supported by automated conformance,
but the manual security sign-off required for a first release is still
`MANUAL_EVIDENCE_REQUIRED`.

## What the reviewer must decide

1. **RNG source (`P-GENERATE-RNG-SOURCE`).** Randomness for generated
   identifiers comes from the operating system CSPRNG, is exactly 96 bits
   (12 bytes) for every generated value, and never from a predictable source.
2. **Fail-closed behaviour (`P-GENERATE-RNG-FAILURE`).** If the CSPRNG cannot be
   opened, read, or does not yield the full byte count, generation raises and
   returns no identifier. There is no fallback, no retry with a weaker source,
   and no `math.random`.

## Files under review

| File | Role |
| --- | --- |
| `src/pikaid/entropy.lua` | Default provider; reads `/dev/urandom` |
| `src/pikaid/init.lua` | Validates the provider result and builds identifiers |

Line numbers are stable for the current `src/` tree; documentation-only commits
do not change them.

### `src/pikaid/entropy.lua`

| Lines | Item |
| --- | --- |
| 16 | `local entropy = {}` — module table |
| 19 | `entropy.BYTES = 12` — required randomness length |
| 22 | `entropy.DEVICE = "/dev/urandom"` — provider device path |
| 32–66 | `entropy.bytes(count)` — the whole provider |
| 35 | `io.open(entropy.DEVICE, "rb")` — binary read, per call |
| 36–42 | open failure → `error("cannot open ...")`, level 0 |
| 44–45 | `file:read(count)` then immediate `file:close()` |
| 47–54 | read failure / `nil` → `error("cannot read ...")` |
| 56–63 | short read (`#data ~= count`) → `error("short read ...")` |
| 65 | success returns exactly `count` bytes |
| 68 | module export |

Review points:

- the device path is opened **for every call**, so there is no long-lived
  handle and no cross-call buffering;
- there is no `math.random`, no time-based seed, no cached bytes, and no
  fallback branch;
- every error path raises with a message; none returns a partial or empty
  string;
- `entropy.DEVICE` is a public field only so tests can point it at a fault
  path; production code never reassigns it.

### `src/pikaid/init.lua`

| Lines | Item |
| --- | --- |
| 30 | `local entropy = require("pikaid.entropy")` |
| 50, 59 | `pikaid.ENTROPY_BYTES = 12`, local `ENTROPY_BYTES` |
| 73–75 | `fail(code, message)` — typed error with `code` |
| 129–155 | `draw_randomness(provider)` — validates the provider result |
| 130 | `pcall(provider, ENTROPY_BYTES)` — asks for exactly 12 bytes |
| 133 | provider raised → `entropy_unavailable` |
| 137–142 | non-string result → `entropy_unavailable` |
| 144–153 | wrong length → `entropy_unavailable` |
| 111–126 | `check_timestamp(timestamp)` — clock value type and range |
| 157–169 | `resolve_timestamp(clock, timestamp)` — clock is separate from RNG |
| 171–176 | `generate(entropy_provider, clock, timestamp)` |
| 178–183 | `generate_binary(entropy_provider, clock, timestamp)` |
| 194–196 | `pikaid.generate(timestamp)` → `generate(entropy.bytes, os.time, timestamp)` |
| 202–204 | `pikaid.generate_binary(timestamp)` → `generate_binary(entropy.bytes, os.time, timestamp)` |
| 218–261 | `pikaid.new(options)` |
| 223 | default provider is `entropy.bytes` |
| 226–232 | caller may inject `options.entropy` / `options.clock` |
| 236–242 | non-function provider/clock rejected with `invalid_type` |
| 249–258 | instance methods call the same `generate` / `generate_binary` |

There is exactly one randomness path: `draw_randomness` → the configured
provider. `pikaid.generate`, `pikaid.generate_binary` and every `pikaid.new`
instance all pass through it. No other module reads randomness.

## Fail-closed propagation chain

```
entropy.bytes(count)                    -- open/read/short-read errors
  -> pcall(provider, 12) in draw_randomness
     -> fail("entropy_unavailable", ...) -- typed error, no fallback
        -> pikaid.generate / generate_binary raises
           -> caller receives no identifier
```

The clock is validated separately (`check_timestamp`, lines 111–126): a failing
clock raises `clock_unavailable`, and a non-integer or out-of-range value raises
`invalid_timestamp` / `timestamp_out_of_range`.

## How to reproduce the evidence

```sh
# native tests, including provider faults and /dev/urandom paths
lua spec/run.lua

# the provider tests specifically
grep -n "entropy provider" spec/generation_spec.lua
```

Relevant existing tests:

| Test | Location |
| --- | --- |
| provider raises / nil / number / table / empty / 11 / 13 bytes | `spec/generation_spec.lua:79–126` |
| `math.random` is never consulted | `spec/generation_spec.lua:215` |
| device open failure | `spec/generation_spec.lua:286` |
| empty device (`/dev/null`) | `spec/generation_spec.lua:298` |
| short read | `spec/generation_spec.lua:310` |

Manual checks a reviewer can run:

```sh
# deterministic injection: no /dev/urandom read, still exactly 12 bytes
lua - <<'LUA'
package.path = "./src/?.lua;./src/?/init.lua;" .. package.path
local pikaid = require("pikaid")
local id = pikaid.new({ entropy = function(n) assert(n == 12); return string.rep("\7", 12) end,
                        clock = function() return 0 end }).generate()
print(id, #pikaid.to_binary(id))
LUA

# fail closed: unusable provider must raise, not degrade
lua - <<'LUA'
package.path = "./src/?.lua;./src/?/init.lua;" .. package.path
local pikaid = require("pikaid")
local ok, err = pcall(function()
  return pikaid.new({ entropy = function() return "" end, clock = function() return 0 end }).generate()
end)
print(ok, tostring(err))
LUA
```

## Platform scope

| Platform | Default provider | Meaning |
| --- | --- | --- |
| Linux | `/dev/urandom` | supported and exercised |
| macOS | `/dev/urandom` | supported and exercised |
| BSD | `/dev/urandom` | same device contract; not exercised by CI |
| Windows | none | generation fails closed; callers must inject a verified CSPRNG |

On Windows the library does **not** silently claim secure generation. Without
`options.entropy`, `io.open("/dev/urandom")` fails and generation raises
`entropy_unavailable`. This is intentional: plain Lua has no portable CSPRNG, so
injecting a verified provider is the caller's responsibility.

## What this packet is not

- It is not a security certification.
- It is not a signature, approval, or reviewer identity.
- A passing automated run does not satisfy the two manual audits; only a named,
  independent human review of the exact release commit does.

Record the reviewed commit SHA in the release record. If the `src/` tree changes
after review, the review no longer applies.
