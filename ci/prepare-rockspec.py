#!/usr/bin/env python3
"""Produce a release-specific LuaRocks rockspec from the reviewed template."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "pikaid-1.0.0-1.rockspec"
MODULE = ROOT / "src/pikaid/init.lua"
SEMVER = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")


def replace_one(text: str, pattern: str, replacement: str) -> str:
    updated, count = re.subn(pattern, lambda _: replacement, text, flags=re.MULTILINE)
    if count != 1:
        raise ValueError(f"Expected exactly one rockspec declaration matching {pattern!r}, found {count}")
    return updated


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="Expected release version (e.g. 1.0.2)")
    args = parser.parse_args()

    source = MODULE.read_text(encoding="utf-8")
    matches = re.findall(r'^\s*pikaid\.VERSION\s*=\s*"([^"]+)"', source, flags=re.MULTILINE)
    if len(matches) != 1 or SEMVER.fullmatch(matches[0]) is None:
        raise ValueError("src/pikaid/init.lua must declare exactly one stable SemVer version")
    version = matches[0]

    if args.version is not None and args.version != version:
        raise ValueError(f"Release v{args.version} does not match source version {version}")

    template = TEMPLATE.read_text(encoding="utf-8")
    if len(re.findall(r'^package\s*=\s*"pikaid"\s*$', template, flags=re.MULTILINE)) != 1:
        raise ValueError("The rockspec template must declare package pikaid")
    if 'url = "git+https://github.com/pikaid/pikaid-lua.git"' not in template:
        raise ValueError("The rockspec template must use the official GitHub source")

    candidate = replace_one(
        template,
        r'^version[ \t]*=[ \t]*"[0-9]+\.[0-9]+\.[0-9]+-[0-9]+"[ \t]*$',
        f'version = "{version}-1"',
    )
    candidate = replace_one(
        candidate,
        r'^[ \t]*tag[ \t]*=[ \t]*"v[0-9]+\.[0-9]+\.[0-9]+"[ \t]*,?[ \t]*$',
        f'  tag = "v{version}",',
    )

    target = ROOT / f"pikaid-{version}-1.rockspec"
    if target.exists():
        if target.read_text(encoding="utf-8") != candidate:
            raise ValueError(f"{target.name} exists but does not match the versioned template")
    else:
        target.write_text(candidate, encoding="utf-8")

    print(target.name)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
,
        f'version = "{version}-1"',
    )
    candidate = replace_one(
        candidate,
        r'^\s*tag\s*=\s*"v[0-9]+\.[0-9]+\.[0-9]+"\s*,?\s*$',
        f'  tag = "v{version}",',
    )

    target = ROOT / f"pikaid-{version}-1.rockspec"
    if target.exists():
        if target.read_text(encoding="utf-8") != candidate:
            raise ValueError(f"{target.name} exists but does not match the versioned template")
    else:
        target.write_text(candidate, encoding="utf-8")

    print(target.name)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
,
        f'  tag = "v{version}",',
    )

    target = ROOT / f"pikaid-{version}-1.rockspec"
    if target.exists():
        if target.read_text(encoding="utf-8") != candidate:
            raise ValueError(f"{target.name} exists but does not match the versioned template")
    else:
        target.write_text(candidate, encoding="utf-8")

    print(target.name)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
,
        f'version = "{version}-1"',
    )
    candidate = replace_one(
        candidate,
        r'^\s*tag\s*=\s*"v[0-9]+\.[0-9]+\.[0-9]+"\s*,?\s*$',
        f'  tag = "v{version}",',
    )

    target = ROOT / f"pikaid-{version}-1.rockspec"
    if target.exists():
        if target.read_text(encoding="utf-8") != candidate:
            raise ValueError(f"{target.name} exists but does not match the versioned template")
    else:
        target.write_text(candidate, encoding="utf-8")

    print(target.name)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
