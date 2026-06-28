# Dependency License Checker (PowerShell)

Parses a dependency manifest, resolves each dependency's license, and reports its
compliance status against an **allow-list** / **deny-list** of licenses.

## What it does

1. **Parse a manifest** — `package.json` (npm `dependencies` + `devDependencies`)
   or `requirements.txt` (pip), extracting each dependency name + version.
2. **Resolve a license** — via `Get-DependencyLicense`, the test seam that is
   *mocked* in unit tests and backed by a deterministic JSON "license database"
   in CI (stand-in for a real registry lookup).
3. **Classify** each license:
   * `approved` — license is on the allow-list
   * `denied`   — license is on the deny-list (deny takes precedence)
   * `unknown`  — license couldn't be resolved, **or** is on neither list
4. **Report** — Text (default), JSON, or Markdown (used for the GitHub Actions
   job summary). Optionally fails the build (`-FailOnViolation`) when any
   dependency is denied.

## Files

| File | Purpose |
| --- | --- |
| `DependencyLicenseChecker.ps1` | The checker: parsing, lookup, classification, reporting, CLI. |
| `DependencyLicenseChecker.Tests.ps1` | Pester unit tests (TDD), incl. the mocked license lookup. |
| `Workflow.Tests.ps1` | Workflow structure tests + end-to-end `act` execution tests. |
| `compliance.config.json` | Default policy (allow/deny) + manifest/license-db paths. |
| `examples/` | Sample manifests + license database. |
| `.github/workflows/dependency-license-checker.yml` | CI pipeline. |
| `act-result.txt` | Captured `act` output for every executed test case. |

## Usage

```pwsh
# Uses compliance.config.json (which points at the manifest + license DB)
./DependencyLicenseChecker.ps1 -ConfigPath compliance.config.json -Format Text

# Override the manifest / license DB, output JSON, and fail on any denial
./DependencyLicenseChecker.ps1 -ManifestPath examples/requirements.txt `
    -LicenseDbPath examples/licenses.json -Format Json -FailOnViolation
```

## Testing

```pwsh
# Fast unit tests for the script logic
Invoke-Pester -Path ./DependencyLicenseChecker.Tests.ps1

# Workflow structure + full end-to-end run through act (Docker required)
Invoke-Pester -Path ./Workflow.Tests.ps1
```

The CI workflow has two jobs: `test` (runs the Pester unit suite) and
`compliance` (runs the checker; `needs: test`). All `run:` steps use
`shell: pwsh`.
