# Dependency License Checker (PowerShell)

Parses a dependency manifest (`package.json` or `requirements.txt`), looks up
each dependency's license, classifies it against configurable allow/deny
lists, and emits a compliance report (`approved` / `denied` / `unknown`).

## Layout

| Path | Purpose |
| --- | --- |
| `DependencyLicenseChecker.psm1` | Module: parsing, license lookup, classification, report |
| `check-licenses.ps1` | CLI entry point (machine-readable `RESULT|…` / `SUMMARY|…` output) |
| `fixtures/` | Test fixtures: sample manifests, license policy config, **mock** license registry DB |
| `tests/DependencyLicenseChecker.Tests.ps1` | Unit tests (TDD cycles 1–5) |
| `tests/Workflow.Tests.ps1` | Workflow structure tests (TDD cycle 6): YAML parse, path refs, actionlint |
| `tests/Act.Tests.ps1` | End-to-end pipeline tests through `act` (writes `act-result.txt`) |
| `.github/workflows/dependency-license-checker.yml` | CI pipeline: Pester tests → license report |

## Design notes

- **TDD**: every function was written test-first (red → green → refactor); the
  Describe blocks in the test files are ordered by cycle.
- **Mocked license lookup**: `Get-DependencyLicense` reads a JSON database
  (`fixtures/mock-license-db.json`) standing in for a real registry API, so
  everything runs hermetically offline. Unit tests additionally stub it with
  Pester `Mock` to test report generation in isolation.
- **Policy**: deny list wins over allow list; unmatched or unresolvable
  licenses are `unknown`. Matching is case-insensitive.
- **Errors**: missing/unparseable manifests, configs, and databases all throw
  meaningful messages; the CLI maps them to exit code 1 (and exit code 2 for
  `-FailOnDenied` with denied licenses present).

## Running

```powershell
# Unit + workflow-structure tests (fast, no Docker)
Invoke-Pester -Path tests/DependencyLicenseChecker.Tests.ps1, tests/Workflow.Tests.ps1

# Full pipeline tests through act (requires Docker; ~1 min; 2 `act push` runs)
Invoke-Pester -Path tests/Act.Tests.ps1

# The checker itself
./check-licenses.ps1 -ManifestPath fixtures/package.json `
    -ConfigPath fixtures/license-config.json `
    -LicenseDatabasePath fixtures/mock-license-db.json
```

The CI workflow runs the same checker; when a `test-input/` directory exists
(created per-case by the act harness) the manifest inside it is checked,
otherwise `fixtures/package.json` is used.
