# Dependency License Checker (PowerShell)

Parses a dependency manifest (`package.json` or `requirements.txt`), looks up each
dependency's license, classifies it against an allow-list / deny-list of licenses,
and produces a compliance report (`approved` / `denied` / `unknown`).

Built test-first with Pester (red/green TDD).

## Layout

| Path | Purpose |
| --- | --- |
| `src/LicenseChecker.psm1` | Core module — parsing, classification, reporting. |
| `src/Invoke-LicenseCheck.ps1` | CLI entry point used by CI. |
| `config/license-config.json` | Allow / deny license lists. |
| `config/license-db.json` | Local license database (name → SPDX id); mockable stand-in for a registry. |
| `fixtures/` | Sample manifests used by tests. |
| `tests/LicenseChecker.Tests.ps1` | Unit tests for the module (license lookup is mocked). |
| `tests/Workflow.Tests.ps1` | Workflow structure tests + `act` integration tests. |
| `.github/workflows/dependency-license-checker.yml` | CI pipeline. |

## Run locally

```powershell
# Unit tests
Invoke-Pester -Path tests/LicenseChecker.Tests.ps1

# CLI
./src/Invoke-LicenseCheck.ps1 `
    -ManifestPath fixtures/package.json `
    -ConfigPath config/license-config.json `
    -LicenseDbPath config/license-db.json
```

## CI

The workflow has two jobs: `unit-tests` (runs Pester) and `compliance`
(runs the checker; depends on `unit-tests`). Steps use `shell: pwsh`.
`tests/Workflow.Tests.ps1` drives the workflow through `nektos/act` for three
fixture cases and asserts exact output; all output is captured to
`act-result.txt`.
