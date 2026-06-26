# Dependency License Checker (PowerShell)

Parses a dependency manifest (`package.json` or `requirements.txt`), looks up each
dependency's license, evaluates it against a configurable **allow-list** /
**deny-list**, and emits a compliance report. Built test-first with Pester and
wired into a GitHub Actions workflow that is validated end-to-end with `act`.

## Layout

| Path | Purpose |
|------|---------|
| `src/DependencyLicenseChecker.psm1` | Core module (parse → lookup → evaluate → report) |
| `Invoke-LicenseCheck.ps1` | CLI entry point; prints a stable, greppable report |
| `config/license-config.json` | Allow-list / deny-list of SPDX licenses |
| `config/license-db.json` | Static license database (the mockable lookup source) |
| `fixtures/` | Sample manifests (`package.json`, `requirements.txt`) |
| `tests/DependencyLicenseChecker.Tests.ps1` | Pester unit tests (TDD) |
| `tests/Workflow.Tests.ps1` | Workflow structure tests + `act` execution harness |
| `tests/test-cases.psd1` | Shared data table for the `act` test cases |
| `.github/workflows/dependency-license-checker.yml` | CI pipeline |

## How it works

The license lookup is deliberately split into two functions so it is easy to test
without any network access:

- `Get-LicenseFromDatabase` — the low-level seam. Tests `Mock` it to simulate an
  external license service; CI points it at `config/license-db.json`.
- `Get-DependencyLicense` — wraps it and normalizes a miss to `UNKNOWN`.

`Test-LicenseStatus` classifies a license as `Approved`, `Denied`, or `Unknown`
(deny-list wins, case-insensitive). `New-ComplianceReport` ties it all together.

## Running the tests

```pwsh
# Fast unit tests (no Docker required)
Invoke-Pester -Path ./tests/DependencyLicenseChecker.Tests.ps1

# Workflow structure + full pipeline run through act (requires Docker + act)
Invoke-Pester -Path ./tests/Workflow.Tests.ps1
```

The workflow harness spins up an isolated git repo per fixture case, runs the
pipeline with `act push`, appends each run to `act-result.txt`, and asserts on
exact expected output (e.g. `SUMMARY approved=1 denied=1 unknown=1 total=3`).

## Running the checker directly

```pwsh
./Invoke-LicenseCheck.ps1 `
    -ManifestPath fixtures/package.json `
    -ConfigPath config/license-config.json `
    -DatabasePath config/license-db.json
```

Exit codes: `0` = report generated (compliant, or non-compliant without
`-FailOnViolation`), `1` = non-compliant with `-FailOnViolation`, `2` = error.
