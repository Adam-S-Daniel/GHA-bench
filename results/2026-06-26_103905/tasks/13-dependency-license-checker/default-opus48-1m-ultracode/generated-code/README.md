# Dependency License Checker

Parses a dependency manifest (npm `package.json` or pip `requirements.txt`),
looks up each dependency's license, classifies it against an **allow / deny**
license policy, and produces a compliance report marking every dependency as
**approved**, **denied**, or **unknown**.

Built test-first (red/green TDD) in **PowerShell** with **Pester**, and wired
into a real CI/CD pipeline via GitHub Actions (validated with `actionlint` and
executed locally with [`act`](https://github.com/nektos/act)).

## Layout

```
src/DependencyLicenseChecker.psm1   # the module (all logic)
bin/check-licenses.ps1              # CLI entry point
config/policy.json                  # allow/deny license policy
config/licenses.json                # mock license database (name -> license)
tests/
  DependencyLicenseChecker.Tests.ps1  # Pester unit tests (TDD, mocked lookup)
  Workflow.Tests.ps1                  # workflow STRUCTURE tests (static)
  Invoke-PesterTests.ps1              # runs the unit suite (used by CI)
  Run-FixtureChecks.ps1              # runs the checker over every fixture (CI)
  run-act-tests.ps1                  # end-to-end act harness -> act-result.txt
  fixtures/manifests/*               # test-case manifests
.github/workflows/dependency-license-checker.yml
```

## How classification works

`Get-LicenseStatus` maps a license to a status (deny takes precedence over
allow, matching is case-insensitive):

| Condition                                   | Status     |
| ------------------------------------------- | ---------- |
| license on the **deny** list                | `denied`   |
| license on the **allow** list               | `approved` |
| license missing, or on neither list         | `unknown`  |

The license lookup (`Get-DependencyLicense`) is the **seam that tests mock** so
the report logic is verified in isolation. In the real CLI it is backed by the
static JSON database in `config/licenses.json` (deterministic and offline).

## Running

```powershell
# Report mode (always exits 0) — prints the compliance report:
./bin/check-licenses.ps1 -ManifestPath tests/fixtures/manifests/01-node-mixed.json

# Enforcement mode — exits 1 if any denied license is present:
./bin/check-licenses.ps1 -ManifestPath package.json -FailOnViolation
```

Exit codes: `0` ok / report produced · `1` violation under `-FailOnViolation` ·
`2` error (missing or invalid file — message on stderr).

## Tests

```powershell
# Unit + structure tests (host):
Invoke-Pester -Path ./tests

# Full pipeline through act, asserting exact per-fixture output -> act-result.txt:
pwsh -File ./tests/run-act-tests.ps1
```

### Methodology

`DependencyLicenseChecker.Tests.ps1` was written red→green: each `It` block was
added and seen to fail before the code that satisfies it was written
(`Read-DependencyManifest` → pip parsing → `Get-LicenseStatus` →
`Get-DependencyLicense` → `New-ComplianceReport` with a **mocked** lookup →
`Format-ComplianceReport` → CLI integration).

### CI pipeline

The workflow runs three dependent jobs — `unit-tests` → `license-check` →
`gate`. Per the task's "all tests run through the pipeline" requirement, the
Pester suite and the fixture compliance checks both execute **inside** the
workflow under `act`. `tests/run-act-tests.ps1` drives a single `act push` run,
captures everything to `act-result.txt`, and asserts the **exact** report lines
for every fixture (e.g. `gpl-tool@1.0.0 | GPL-3.0 | denied`), that `act` exited
`0`, and that every job reports `Job succeeded`.
