# Dependency License Checker (PowerShell)

Parses dependency manifests (`package.json`, `requirements*.txt`), looks up
each dependency's license in a mock JSON license database, classifies it
against configured allow/deny lists, and emits a compliance report
(`Approved` / `Denied` / `Unknown`). Built red/green TDD-first with Pester.

## Layout

| Path | Purpose |
|---|---|
| `src/LicenseChecker.psm1` | Core module: parsing, lookup, classification, report |
| `scripts/Invoke-LicenseCheck.ps1` | CLI entry point used by CI |
| `config/license-config.json` | Allow/deny license lists |
| `fixtures/mock-licenses.json` | Mock license database (name → SPDX id) |
| `fixtures/case*/` | Per-case manifest fixtures for the act pipeline tests |
| `tests/LicenseChecker.Tests.ps1` | Unit tests (21) — one Describe per TDD cycle |
| `tests/Workflow.Tests.ps1` | Workflow structure tests (13) incl. actionlint |
| `tests/Act.Tests.ps1` | End-to-end pipeline tests (29) via `act push` |
| `.github/workflows/dependency-license-checker.yml` | CI workflow |
| `act-result.txt` | Captured act output artifact |

## Usage

```powershell
./scripts/Invoke-LicenseCheck.ps1 -Path test-input `
    -ConfigPath config/license-config.json `
    -LicenseDatabasePath fixtures/mock-licenses.json   # add -FailOnDenied to gate
```

Output lines: `RESULT|<name>|<version>|<license>|<status>` and
`SUMMARY|Approved=n|Denied=n|Unknown=n|Total=n`. Deny list beats allow list;
unresolvable licenses report as `UNKNOWN`/`Unknown`.

## Tests

```powershell
Invoke-Pester -Path tests/LicenseChecker.Tests.ps1, tests/Workflow.Tests.ps1  # fast
Invoke-Pester -Path tests/Act.Tests.ps1   # runs 3 Docker/act pipelines (~2 min)
```

The CI workflow runs the unit tests in a `pwsh` job, then a dependent job
generates the compliance report for manifests committed under `test-input/`.
