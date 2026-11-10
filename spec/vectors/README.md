# Vendored conformance fixtures

These files are unmodified copies of the official pikaid interoperability
fixtures from the PHP implementation. They are test data only; the Lua library
does not ship them.

| File                   | Source                                                                                                                        |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `pikaid-v1.json`       | `pikaid/pikaid-php@e3f843edeb5157a5d2d25196cac0d69580810a95:tests/vectors/pikaid-v1.json` (release `v1.2.0`)                    |
| `pikaid-v1.schema.json`| `pikaid/pikaid-php@e3f843edeb5157a5d2d25196cac0d69580810a95:tests/vectors/pikaid-v1.schema.json` (release `v1.2.0`)              |

Retrieved from:

- <https://github.com/pikaid/pikaid-php/blob/v1.2.0/tests/vectors/pikaid-v1.json>
- <https://github.com/pikaid/pikaid-php/blob/v1.2.0/tests/vectors/pikaid-v1.schema.json>

SHA-256:

```text
b0c9dfdd063613424414fef5c9065fbd2f81d645d0ab42b34e27cde715613500  pikaid-v1.json
4441d4dbaa6c5450ae9cbfb2438c53bc0421bba2b7fcc9ef9b158e5d1de0759e  pikaid-v1.schema.json
```

The `pikaid-v1` filename is historical. As stated by pikaid specification
revision 1.0.4 (commit `17014d76f568c3ac9f9ce2927c1a018fdbc36d1d`), the
identifier format is immutable and unversioned; the version in the filename
refers to the fixture collection, not to the identifiers.

The canonical specification is the normative reference. Where a fixture and the
specification disagree, the specification wins.

`spec/tools/generate_reference_cases.py` produces the separate
`spec/fixtures/reference-cases.json` oracle with Python's arbitrary-precision
integers; that file is generated independently from the Lua implementation.
