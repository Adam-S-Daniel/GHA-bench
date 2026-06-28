# Dependency License Checker (PowerShell)

Parses a dependency manifest (`package.json` or `requirements.txt`), resolves each
dependency's license via a **mockable** local license database, classifies every
license against an allow/deny policy, and emits a deterministic compliance report.

Built test-first (red/green TDD) with **Pester**, and exercised end-to-end in a
real GitHub Actions pipeline via **act**.

## Layout

| Path | Purpose |
|------|---------|
| `src/LicenseChecker.psm1` | Function library (parse, license lookup, classify, report). |
| `Invoke-LicenseCheck.ps1` | CLI entry point that wires the functions together. |
| `config/license-config.json` | License policy: `{ "allow": [...], "deny": [...] }`. |
| `fixtures/` | Default manifest + mock license database. |
| `tests/LicenseChecker.Tests.ps1` | Unit + CLI integration tests. |
| `tests/Workflow.Tests.ps1` | Workflow structure / actionlint tests. |
| `.github/workflows/dependency-license-checker.yml` | CI pipeline. |
| `Run-ActTests.ps1` | Harness that runs the workflow through `act` per fixture case. |

## How the "mock" works

`Get-DependencyLicense` is the seam: in unit tests it is replaced with a Pester
`Mock`; at runtime it reads a local JSON database (`{ "<package>": "<license>" }`)
instead of hitting a network registry. This keeps the tool fully deterministic and
offline-friendly.

## Status classification

* **approved** — license is on the allow-list.
* **denied** — license is on the deny-list.
* **unknown** — license is on neither list, or no license could be found.

## Usage

```pwsh
./Invoke-LicenseCheck.ps1 `
    -ManifestPath fixtures `
    -ConfigPath   config/license-config.json `
    -LicenseDbPath fixtures/license-db.json
```

`-ManifestPath` accepts a file or a directory (the first `package.json` /
`requirements.txt` found is used). Add `-FailOnViolation` to exit non-zero when a
denied license is present (for hard-gating a pipeline). Exit codes: `0` success,
`1` denied license under `-FailOnViolation`, `2` usage/IO error.

## Running the tests

```pwsh
Invoke-Pester -Path tests/        # unit + structure tests
pwsh -File ./Run-ActTests.ps1     # full workflow via act -> writes act-result.txt
```
