# Dependency License Compliance Checker (PowerShell)

Parses a dependency manifest (`package.json` or `requirements.txt`), resolves
each dependency's license, checks it against an **allow-list / deny-list**
policy, and produces a compliance report classifying every dependency as
**Approved**, **Denied**, or **Unknown**.

The license lookup is intentionally backed by a small JSON database (a *mock*
license source), keeping the whole tool deterministic and offline — safe to run
in an isolated CI container with no network or secrets.

## Layout

| Path | Purpose |
|------|---------|
| `LicenseChecker.psm1` | Core library (parse / lookup / classify / report). |
| `Invoke-LicenseCheck.ps1` | CLI entry point the workflow invokes. |
| `config/license-config.json` | Policy: `allowList` / `denyList` of SPDX ids. |
| `fixtures/license-db.json` | Mock license-lookup database. |
| `fixtures/*` | Fixtures used by the unit tests. |
| `examples/package.json` | Default manifest analysed when none is injected. |
| `cases/*` | Fixture manifests for the end-to-end act test cases. |
| `tests/LicenseChecker.Tests.ps1` | Pester **unit** tests (run in CI). |
| `tests/WorkflowStructure.Tests.ps1` | Static workflow-structure + actionlint tests. |
| `tests/ActHarness.Tests.ps1` | End-to-end tests that drive the workflow via `act`. |
| `.github/workflows/dependency-license-checker.yml` | The CI/CD pipeline. |
| `act-result.txt` | Captured output of every end-to-end `act` run (artifact). |

## Core functions (`LicenseChecker.psm1`)

- `Get-DependencyList` – parse a manifest into `Name`/`Version` records.
- `Get-DependencyLicense` – resolve a package's license from the (mockable) database.
- `Test-LicenseStatus` – classify a license as `Approved` / `Denied` / `Unknown` (deny wins ties).
- `New-ComplianceReport` – orchestrate the above into a structured report.
- `Format-ComplianceReport` – render the report as machine-parseable text.

## Report format

```
=== Dependency License Compliance Report ===
Manifest: <path>
DEP | <name> | <version> | <license> | <status>
...
SUMMARY | Total: N | Approved: A | Denied: D | Unknown: U
RESULT: PASS|FAIL        # FAIL when any dependency is Denied
```

## Running the tests

All tests run with `Invoke-Pester`:

```powershell
# Fast: unit + workflow-structure tests only (no Docker needed)
Invoke-Pester -Path tests/LicenseChecker.Tests.ps1, tests/WorkflowStructure.Tests.ps1

# Full: everything, including the end-to-end act harness (needs Docker + act)
Invoke-Pester -Path tests

# Convenience wrapper (-IncludeAct to also run the act harness)
./RunTests.ps1 -IncludeAct
```

The end-to-end harness (`tests/ActHarness.Tests.ps1`) builds a throwaway git
repo per case, injects that case's manifest via `act --env MANIFEST_FILE=...`,
runs `act push --rm`, appends the output to `act-result.txt`, and asserts the
exact expected report values plus `Job succeeded` for both jobs.

## Running the checker directly

```powershell
./Invoke-LicenseCheck.ps1 `
  -ManifestPath examples/package.json `
  -ConfigPath  config/license-config.json `
  -LicenseDbPath fixtures/license-db.json `
  -FailOnDenied        # optional: exit 1 if any denied license is found
```

## CI/CD workflow

`.github/workflows/dependency-license-checker.yml` runs two dependent jobs:

1. **test** – runs the Pester unit tests.
2. **license-check** (`needs: test`) – resolves the manifest, runs the checker,
   and publishes the report to the job summary.

It triggers on `push`, `pull_request`, a weekly `schedule`, and
`workflow_dispatch` (with a `manifest` input), uses least-privilege
`contents: read` permissions, and every `run:` step uses `shell: pwsh`.
