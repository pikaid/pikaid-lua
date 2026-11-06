#!/usr/bin/env python3
"""Generate independent reference cases for the pikaid Lua test suite.

This script is deliberately not part of the installed library and is not used
by the Lua implementation. It derives expected identifiers and binary values
from Python's arbitrary-precision integers, following the pikaid 1.0.4 rules
directly, so the Lua tests are checked against an oracle written independently
from the code under test.

Usage (from the repository root):

    python3 spec/tools/generate_reference_cases.py

The output is deterministic and committed as
spec/fixtures/reference-cases.json.
"""

from __future__ import annotations

import json
import random
from pathlib import Path

ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"
MAX_TIMESTAMP = 36**7 - 1
ENTROPY_BYTES = 12
BINARY_LENGTH = 17
SEED = 20261106

EDGE_TIMESTAMPS = [
    0,
    1,
    35,
    36,
    1295,
    1296,
    46655,
    46656,
    1679615,
    1679616,
    1_700_000_000,
    MAX_TIMESTAMP - 1,
    MAX_TIMESTAMP,
]

EDGE_ENTROPY = [
    bytes(12),
    bytes(11) + b"\x01",
    bytes(11) + b"\x10",
    b"\x80" + bytes(11),
    bytes(11) + b"\xff",
    bytes.fromhex("ffffffffffffffffffffffff"),
    bytes.fromhex("0102030405060708090a0b0c"),
    bytes.fromhex("aaaaaaaaaaaa555555555555"),
    bytes.fromhex("7fffffffffffffffffffffff"),
    bytes.fromhex("800000000000000000000000"),
]


def base36(value: int, width: int) -> str:
    digits = []
    for _ in range(width):
        value, remainder = divmod(value, 36)
        digits.append(ALPHABET[remainder])
    if value != 0:
        raise ValueError("value does not fit")
    return "".join(reversed(digits))


def make_case(name: str, timestamp: int, entropy: bytes) -> dict[str, object]:
    if not 0 <= timestamp <= MAX_TIMESTAMP:
        raise ValueError("timestamp out of range")
    if len(entropy) != ENTROPY_BYTES:
        raise ValueError("entropy length")
    identifier = base36(timestamp, 7) + base36(int.from_bytes(entropy, "big"), 19)
    binary = timestamp.to_bytes(5, "big") + entropy
    if len(binary) != BINARY_LENGTH:
        raise ValueError("binary length")
    return {
        "name": name,
        "timestamp": timestamp,
        "randomness_hex": entropy.hex(),
        "id": identifier,
        "bin_hex": binary.hex(),
    }


def main() -> None:
    cases = []

    for timestamp in EDGE_TIMESTAMPS:
        for entropy in EDGE_ENTROPY:
            cases.append(
                make_case(
                    f"ts-{timestamp}-entropy-{entropy.hex()[:8]}",
                    timestamp,
                    entropy,
                )
            )

    rng = random.Random(SEED)
    for index in range(160):
        timestamp = rng.randrange(0, MAX_TIMESTAMP + 1)
        entropy = bytes(rng.getrandbits(8) for _ in range(ENTROPY_BYTES))
        cases.append(make_case(f"random-{index:03d}", timestamp, entropy))

    document = {
        "meta": {
            "spec_revision": "1.0.4",
            "generator": "spec/tools/generate_reference_cases.py",
            "seed": SEED,
            "oracle": "Python arbitrary-precision integers, independent of the Lua implementation",
        },
        "cases": cases,
    }

    output = Path(__file__).resolve().parents[1] / "fixtures" / "reference-cases.json"
    output.write_text(json.dumps(document, indent=2) + "\n", encoding="ascii")

    print(f"wrote {len(cases)} cases to {output}")
    for timestamp in EDGE_TIMESTAMPS:
        print(f"  timestamp {timestamp:>11} -> {base36(timestamp, 7)}")
    for entropy in EDGE_ENTROPY:
        print(f"  entropy {entropy.hex()} -> {base36(int.from_bytes(entropy, 'big'), 19)}")


if __name__ == "__main__":
    main()
