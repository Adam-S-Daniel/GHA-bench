# Environment Matrix Generator (PowerShell)

Generates a GitHub Actions `strategy.matrix` JSON document from a
configuration describing OS options, language versions, and feature flags,
with include/exclude rules, `max-parallel`, `fail-fast`, and a maximum-size
guard. Built with red/green TDD using Pester.

## Usage

```powershell
./Invoke-MatrixGenerator.ps1 -ConfigPath fixtures/ci-config.json [-OutputPath matrix.json]
```

Prints the complete strategy JSON (compressed) to stdout, e.g.:

```json
{"fail-fast":true,"max-parallel":4,"matrix":{"include":[{"os":"ubuntu-22.04","version":"3.11"}, ...]}}
```

Exit code 0 on success; 1 with a meaningful stderr message on any error
(missing/malformed config, invalid options, empty or oversize matrix).

## Configuration schema

| Key                | Type       | Required | Meaning                                                            |
|--------------------|------------|----------|--------------------------------------------------------------------|
| `os`               | `string[]` | yes      | OS axis -> matrix key `os`                                          |
| `languageVersions` | `string[]` | yes      | Version axis -> matrix key `version`                                |
| `featureFlags`     | `string[]` | no       | Flags axis -> matrix key `flags`                                    |
| `exclude`          | `object[]` | no       | Partial-match removal rules (GitHub Actions semantics)              |
| `include`          | `object[]` | no       | Merge-or-append rules (GitHub-Actions-like semantics)               |
| `failFast`         | `bool`     | no       | -> `fail-fast` (default `true`)                                     |
| `maxParallel`      | `int`      | no       | -> `max-parallel` (omitted when unset)                              |
| `maxMatrixSize`    | `int`      | no       | Size cap; default 256 (the real GitHub Actions matrix limit)        |

Rule semantics:

- **exclude**: a combination is removed when *every* key in a rule matches it
  (rules may name any subset of axis keys).
- **include**: a rule whose axis keys match existing combinations merges its
  extra keys into them (never overwriting axis values); a rule matching
  nothing is appended as a brand-new combination.

## Files

- `Invoke-MatrixGenerator.ps1` — CLI entry point
- `src/MatrixGenerator.ps1` — core library (axis expansion, rules, validation, assembly)
- `tests/MatrixGenerator.Tests.ps1` — unit suite, one Describe per TDD cycle
- `tests/Workflow.Tests.ps1` — workflow structure tests + actionlint gate
- `tests/ActPipeline.Tests.ps1` — end-to-end harness: each test case runs the
  workflow via `act push` in an isolated temp git repo and asserts exact
  outputs; writes the required `act-result.txt` artifact
- `fixtures/` — test-case configs and their exact expected JSON outputs
- `.github/workflows/environment-matrix-generator.yml` — the pipeline:
  `test` (Pester) -> `generate-matrix` (runs the script, publishes the JSON as
  a job output) -> `consume-matrix` (a real dynamic matrix via
  `${{ fromJSON(...) }}`, one leg per combination)

## Running the tests

```powershell
Invoke-Pester                                      # everything (needs Docker + act)
Invoke-Pester -Path tests/MatrixGenerator.Tests.ps1  # unit tests only
```
