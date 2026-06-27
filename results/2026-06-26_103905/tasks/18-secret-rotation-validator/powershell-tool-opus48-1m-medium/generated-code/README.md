# Secret Rotation Validator

A PowerShell tool that reads a set of secrets with rotation metadata, classifies
each by urgency (**expired / warning / ok**), produces a rotation report grouped
by urgency, and renders it as a **markdown table** or **JSON**. Built with
red/green TDD using Pester, and wired into a GitHub Actions pipeline validated
locally with `act`.

## Files

| File | Purpose |
| --- | --- |
| `SecretRotation.psm1` | Core module: classification, report building, formatting, config loading. |
| `Invoke-RotationValidator.ps1` | CLI entry point. Exit code = worst urgency (2 expired / 1 warning / 0 ok / 3 error). |
| `SecretRotation.Tests.ps1` | 21 Pester unit tests for the module (written test-first). |
| `Workflow.Tests.ps1` | Workflow structure tests + actionlint check + `act` execution harness. |
| `fixtures/secrets.json` | Default mock secrets config (mixed urgencies). |
| `fixtures/all-ok.json` | Mock config where every secret is healthy. |
| `.github/workflows/secret-rotation-validator.yml` | CI pipeline (push / PR / daily schedule / manual). |
| `act-result.txt` | Captured `act` output for all three test cases (generated). |

## Data model

Each secret in the JSON config:

```json
{ "name": "prod-db-password", "lastRotated": "2026-01-01", "rotationPolicyDays": 30, "requiredBy": ["web", "api"] }
```

Classification (given a reference "now" and a configurable warning window):

- `expiryDate = lastRotated + rotationPolicyDays`
- `daysUntilExpiry < 0` &rarr; **expired**
- `0 <= daysUntilExpiry <= warningDays` &rarr; **warning**
- `daysUntilExpiry > warningDays` &rarr; **ok**

## Running

```powershell
# Unit tests
Invoke-Pester -Path ./SecretRotation.Tests.ps1

# Generate a report directly
pwsh ./Invoke-RotationValidator.ps1 -ConfigPath fixtures/secrets.json `
    -WarningDays 14 -Format markdown -ReferenceDate 2026-06-26

# Full workflow + act pipeline tests (runs `act push` for 3 cases)
Invoke-Pester -Path ./Workflow.Tests.ps1
```

`-ReferenceDate` makes "now" injectable so reports are deterministic against the
committed fixtures (CI defaults it via the `REFERENCE_DATE` env var).

## CI pipeline

The workflow checks out the repo, verifies Pester is available, runs the unit
tests, then generates the rotation report and publishes it to the job summary.
All `run:` steps use `shell: pwsh`. The `act` harness (`Workflow.Tests.ps1`)
spins up an isolated temp git repo per test case, runs `act push --rm`, captures
output to `act-result.txt`, and asserts on exact expected values plus
`Job succeeded`.
