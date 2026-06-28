# Dependency License Compliance Checker (PowerShell)

Parses a dependency manifest (`package.json` or `requirements.txt`), looks up
each dependency's license (mocked for determinism), classifies it against an
allow-list / deny-list, and produces a compliance report. Built test-first with
Pester and wired into a GitHub Actions pipeline that is validated end-to-end
with `act`.

## Layout

| Path | Purpose |
|------|---------|
| `src/LicenseChecker.psm1` | Core module: parsing, license lookup, classification, report building/formatting. |
| `Invoke-LicenseChecker.ps1` | CLI entry point — loads config + license DB, scans a manifest, prints/saves the report. |
| `config/license-config.json` | Allow-list and deny-list of SPDX license ids. |
| `config/license-db.json` | Mock license database (package → license). Stands in for a real registry lookup. |
| `fixtures/package.json` | Default manifest scanned by the workflow. |
| `tests/LicenseChecker.Tests.ps1` | Pester **unit** tests (run inside CI via `act`). |
| `integration/Workflow.Tests.ps1` | Workflow **structure + actionlint + act** integration tests (run locally). |
| `.github/workflows/dependency-license-checker.yml` | CI pipeline. |
| `act-result.txt` | Captured `act` output from the last integration run (required artifact). |

## How it works

`Get-Dependencies` parses the manifest into name/version records.
`Resolve-DependencyLicense` is the **mockable seam** — in production it would
query npm/PyPI; here it reads the in-memory database from `config/license-db.json`
(and Pester `Mock`s it in unit tests). `Get-LicenseStatus` classifies a license
as `approved` / `denied` / `unknown` (deny-list wins; unknown does not by itself
break compliance — only a denied license does). `New-ComplianceReport` ties these
together; `Format-ComplianceReport` renders the stable text the pipeline asserts on.

## Running locally

```pwsh
# Unit tests (TDD suite)
Invoke-Pester -Path tests/LicenseChecker.Tests.ps1

# Generate a report directly
./Invoke-LicenseChecker.ps1 -ManifestPath fixtures/package.json `
    -ConfigPath config/license-config.json -LicenseDbPath config/license-db.json

# Use as a CI gate (non-zero exit on a denied license)
./Invoke-LicenseChecker.ps1 -ManifestPath fixtures/package.json `
    -ConfigPath config/license-config.json -LicenseDbPath config/license-db.json -FailOnDenied
```

## CI pipeline

The workflow has two jobs:

1. **unit-tests** — runs the Pester suite inside the container.
2. **compliance-report** (`needs: unit-tests`) — runs the checker on the manifest
   and prints the report. The manifest path can be overridden per run with the
   `MANIFEST_PATH` environment variable (used by the integration harness).

### Validating the workflow

```pwsh
actionlint .github/workflows/dependency-license-checker.yml   # static check
Invoke-Pester -Path integration/Workflow.Tests.ps1            # structure + 3 act runs
```

The integration harness builds a throwaway git repo per test case, runs
`act push --rm`, appends the output to `act-result.txt`, and asserts on exact
expected values (e.g. `copyleft-lib@1.0.0 [GPL-3.0] -> DENIED`,
`Total: 2 | Approved: 1 | Denied: 1 | Unknown: 0`, `Compliance: FAIL`) plus that
every job reports `Job succeeded`.

> `.actrc` pins the runner to the prebuilt `act-ubuntu-pwsh:latest` image and sets
> `--pull=false` so `act` uses the local image instead of trying to pull it.
