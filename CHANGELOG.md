# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-11-09

### Added

- Official Lua implementation of pikaid specification revision 1.0.4.
- Strict text and 17-byte binary validation, generation, and lossless conversion.
- Fail-closed entropy from `/dev/urandom`, with an injectable CSPRNG for other platforms.
- Conformance suite covering the official fixtures, an independent Python oracle, and edge cases.
- SHA-256 pinning of every vendored fixture, so an accidental edit or line-ending
  conversion is reported before any conformance assertion runs.
- Executable README checks: the documented quick start and provider example run in CI
  against both a checkout and an installed package.
- Negative cases for CR, LF, CRLF, and multi-byte zero-width characters.
- Generation conformance over all 290 independent oracle cases.
- Clock-drift and provider-option immutability tests.
- CI across Lua 5.3, 5.4, and 5.5 on Linux and macOS, with lint, oracle-regeneration,
  coverage, packaging, installed-consumer, archive-hygiene, and 32-bit-guard jobs.
- `RELEASING.md`, a non-destructive tag, build and publish runbook with the tag and
  rockspec revision policy.
- `docs/csprng-review-packet.md`, the file/line map an independent reviewer needs for
  the two manual CSPRNG audits.

### Changed

- `VERSION` is now `1.0.0`; the rockspec is `pikaid-1.0.0-1.rockspec` and pins the
  `v1.0.0` release tag.
- A `LUA_32BITS` interpreter is now rejected at load time with a clear error, rather
  than failing later during encoding or producing corrupt values.
- CI downloads Lua from `lua.org` with retries and falls back to the official GitHub
  mirror of the same release.
- Added `.gitattributes` so the vendored fixtures and sources keep LF endings on every
  platform, keeping their pinned digests stable.
- Root `.ai/` working data and local `opencode.jsonc` are ignored explicitly and are
  excluded from source archives and packages.

### Notes

- No release tag or LuaRocks package has been published yet. Publishing requires tag,
  namespace, and credential ownership that this repository's CI does not hold.

[1.0.0]: https://github.com/pikaid/pikaid-lua/releases/tag/v1.0.0
