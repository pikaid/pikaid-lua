# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Official Lua implementation of pikaid specification revision 1.0.4.
- Strict text and 17-byte binary validation, generation, and lossless conversion.
- Fail-closed entropy from `/dev/urandom`, with an injectable CSPRNG for other platforms.
- Conformance suite covering the official fixtures, an independent oracle, and edge cases.
- CI across Lua 5.3, 5.4, and 5.5, including lint, coverage, and LuaRocks consumer smoke tests.

### Notes

- No release tag or LuaRocks package has been published yet. The rockspec tracks
  `main` until an immutable `v0.1.0` tag exists.

[Unreleased]: https://github.com/pikaid/pikaid-lua
