# Releasing pikaid for Lua

This is the non-destructive release runbook for `pikaid-lua`. Nothing here has
been executed against the public repository: the first release tag, GitHub
release and LuaRocks publication all require explicit owner approval for that
exact action. The commands below are written so that a failure at any step
leaves the public state unchanged.

The identifier format is immutable and unversioned. A new package version
changes the release label only; it must never change the 26-character Base36
text form or the 17-byte binary layout.

## Release gates (all must be genuinely green)

| Gate | What proves it |
| --- | --- |
| Spec compliance | `python3 tools/verify_vectors.py --expect-status OFFICIAL --expect-package-revision 1.0.0 --expect-spec-revision 1.0.4` exits 0 in the pinned suite |
| Automated official conformance | `tools/run_adapter.py --automated-only` against `spec/tools/jsonl_adapter.lua` exits 0 |
| Native + platform support | `lua spec/run.lua` green on Lua 5.3/5.4/5.5, `LUA_32BITS` guard refuses to load |
| Security human approval | A named independent human review of the CSPRNG paths recorded for the exact commit (see `docs/csprng-review-packet.md`) |
| Hosted CI on final SHA | A `push` run with every job and step green on the exact commit being tagged |
| Consumer/package | Binary and source rocks install, and a consumer outside the checkout can generate, validate, convert and compare |
| Publication authorization | The repository owner has authorized the tag and the LuaRocks upload |

`--automated-only` conformance and a green tree are *not* a release sign-off.
The two manual audits `P-GENERATE-RNG-SOURCE` and `P-GENERATE-RNG-FAILURE`
stay outstanding until a human reviewer signs them off.

## 1. Confirm the exact commit

```sh
git fetch origin
git status --porcelain=v1 -uall          # must be empty
git rev-parse HEAD                       # candidate commit
git rev-parse origin/main                # must equal HEAD
```

Re-run the local gates on that commit (the pinned suite, native matrix, lint,
coverage, mutations, packaging and consumer) and record the SHAs in the release
record. Do not tag a commit whose CI has not run green.

## 2. Confirm hosted CI on the exact SHA

```sh
gh run list --commit "$(git rev-parse HEAD)" --limit 5
gh run view <run-id> --json status,conclusion,headSha,jobs
```

Every job must report `conclusion: success` with a non-empty `steps` list. A
run whose jobs have `steps: []` is an account/billing refusal, not a pass; stop
and restore GitHub Actions billing first.

## 3. Record the human CSPRNG review

The reviewer must read the exact commit recorded in step 1 and sign a
non-sensitive record covering:

- the provider in `src/pikaid/entropy.lua` (open/read/short-read failure paths);
- every call site in `src/pikaid/init.lua` (`draw_randomness`, `generate`,
  `generate_binary`, `pikaid.generate`, `pikaid.generate_binary`, `pikaid.new`);
- fail-closed behaviour: no fallback, no `math.random`, error propagation.

Do not write a reviewer name, signature or approval that did not happen. If no
reviewer has signed, the release stays `NO-GO`.

## 4. Create the tag (owner action, once)

Create an annotated tag on the exact reviewed commit. Never move, delete or
re-point an existing release tag.

```sh
sha="$(git rev-parse HEAD)"
git tag -a v1.0.0 "$sha" -m "pikaid-lua 1.0.0 (specification 1.0.4)"
git tag --list v1.0.0
git show --no-patch --format='%H %d' v1.0.0
git push origin v1.0.0                   # owner-approved action
git ls-remote --tags origin v1.0.0       # verify the remote tag points at "$sha"
```

If the tag already exists locally or remotely, stop. A wrong tag cannot be
"fixed" by force; the repository policy forbids rewriting it.

## 5. Build and verify the source rock from the tag

`luarocks pack` resolves `source.url`/`source.tag` from the rockspec, so it can
only succeed once the tag exists.

```sh
luarocks pack pikaid-1.0.0-1.rockspec
unzip -Z1 pikaid-1.0.0-1.src.rock       # expect the tagged tree, no .ai/, no .git/
luarocks install pikaid-1.0.0-1.src.rock --tree=/tmp/pikaid-release
```

Then run a consumer outside the checkout against
`/tmp/pikaid-release/share/lua/<version>/`. `luarocks make` is the local
development path and ignores `source.tag`; it is not a tag check.

A dry run of exactly this archive path is possible without a public tag: create
a *private, non-public* local mirror in `.ai/tmp`, tag the exact commit there,
and point a temporary copy of the rockspec at that mirror with
`git+file:///...`. Label the result `DRY-RUN`; it validates archive content and
installability but is not a published source rock.

## 6. Publish to LuaRocks (owner action, explicit approval required)

```sh
luarocks upload pikaid-1.0.0-1.src.rock --api-key="$LUAROCKS_API_KEY"
```

Requirements before this command:

- the tag from step 4 exists and points at the reviewed commit;
- the source rock from step 5 was built from that tag and installed cleanly;
- the owner has explicitly approved this upload for this exact version;
- the API key is the owner's credential and is never committed or logged.

Published rocks are immutable. Do not delete and re-upload.

## 7. GitHub release (owner action, optional)

A GitHub release is a separate authorized action. Use the same `v1.0.0` tag and
the `CHANGELOG.md` entry; do not attach generated build output that the
repository does not track.

## Version and revision policy

- **Text or behaviour change:** new version, new commit, new tag. Never reuse a
  version.
- **Rockspec-only fix (metadata, dependencies, build):** keep the tag, bump the
  rockspec revision (`1.0.0-1` → `1.0.0-2`), rebuild and publish the new
  revision. The tag is not moved.
- **Release tag:** annotated, created once, never rewritten.
- **LuaRocks:** a published revision is immutable; corrections use a new
  rockspec revision.

## Failure handling

| Failure | Correct response |
| --- | --- |
| CI jobs have zero steps | Treat as `BLOCKED_EXTERNAL`; restore Actions billing; do not tag |
| Tag pushed at the wrong commit | Stop; do not force-push tags; escalate to the owner |
| Source rock fails to build from the tag | Fix the rockspec at a new revision; do not move the tag |
| Consumer fails against the installed tree | Do not publish; fix and rebuild |
| Reviewer unavailable | Release stays `NO-GO`; automated passing does not substitute |
| LuaRocks upload rejected | No public artifact exists; fix and retry with approval |

## Record to keep

Final commit SHA, tag object SHA, CI run URL, reviewer record path, source and
binary rock SHA-256 digests, install tree, consumer transcript, LuaRocks
upload response. Keep the report and evidence outside the release tag; `.ai/`
is never committed.
