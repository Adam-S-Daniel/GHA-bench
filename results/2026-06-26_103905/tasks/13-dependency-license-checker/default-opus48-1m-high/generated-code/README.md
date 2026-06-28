# Dependency License Checker

Parses a dependency manifest (`package.json` or `requirements.txt`), looks up
each dependency's license, classifies it against an allow-list / deny-list
policy, and prints a compliance report (`approved` / `denied` / `unknown`).

Built with **PowerShell + Pester** using red/green TDD, and wired into a
GitHub Actions pipeline that runs end-to-end under `act`.

## Files

| File | Purpose |
| --- | --- |
| `LicenseChecker.psm1` | Core logic: parsing, config/db loading, classification, formatting. |
| `Invoke-LicenseCheck.ps1` | CI entry point: auto-detects manifest/config/db in a project dir, prints the report, optionally fails on denied licenses. |
| `LicenseChecker.Tests.ps1` | Pester unit tests (TDD). The license lookup is **mocked** for determinism. |
| `Workflow.Structure.Tests.ps1` | Pester tests asserting the workflow's YAML structure + actionlint. |
| `.github/workflows/dependency-license-checker.yml` | CI pipeline: `unit-tests` job (Pester) → `compliance-report` job (the checker). |
| `run-act-tests.sh` | Integration harness: runs the workflow via `act` for each fixture case and asserts exact output. |
| `package.json`, `license-config.json`, `license-db.json` | Baseline fixtures used by the default workflow run. |

## Design

- **Status precedence** (`Get-LicenseStatus`): a `null`/empty license is
  `unknown`; deny-list always wins over allow-list; allow-list → `approved`;
  otherwise `unknown`. Matching is case-insensitive.
- **The mock seam** is `Get-DependencyLicense`. In production it resolves a
  license from a local `license-db.json` (a stand-in for a registry API),
  trying a `name@version` key then falling back to `name`. In tests it is
  replaced by a Pester `Mock` so nothing external is contacted.
- **Errors** are surfaced with meaningful messages (missing files, malformed
  JSON, unsupported manifest types) and distinct exit codes from the entry
  script (`0` ok, `1` denied-with-FailOnDenied, `2` input/config error).

## Config formats

```jsonc
// license-config.json — the policy
{ "allow": ["MIT", "Apache-2.0"], "deny": ["GPL-3.0", "AGPL-3.0"] }

// license-db.json — mocked license lookup data
{ "express@4.18.2": "MIT", "lodash": "MIT" }
```

## Running

```bash
# Unit + structure tests (host)
pwsh -c "Invoke-Pester -Path ./LicenseChecker.Tests.ps1,./Workflow.Structure.Tests.ps1"

# Full pipeline through act (writes act-result.txt)
./run-act-tests.sh --reset all
```

Every test case is exercised through the GitHub Actions workflow via `act`;
the combined, delimited output is saved to `act-result.txt`.
