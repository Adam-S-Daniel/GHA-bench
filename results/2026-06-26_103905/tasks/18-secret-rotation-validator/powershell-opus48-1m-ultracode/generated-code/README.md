# Secret Rotation Validator

A PowerShell tool that reads a configuration of secrets (name, last-rotated
date, rotation policy in days, and the services that require them), flags every
secret as **expired**, **warning**, or **ok**, and produces a rotation report —
as a Markdown table or as JSON — with notifications grouped by urgency.

Built test-first with Pester, and wired into a GitHub Actions pipeline that is
exercised locally with [`act`](https://github.com/nektos/act).

## Files

| File | Purpose |
| --- | --- |
| `SecretRotationValidator.ps1` | The validator. Dual-purpose: dot-source it to load the functions, or run it directly as a CLI. |
| `SecretRotationValidator.Tests.ps1` | Pester unit suite (42 tests). Also run inside the pipeline. |
| `fixtures/*.json` | Mock secret inventories (`mixed`, `all-ok`, `all-expired`) + the active `config.json`. |
| `.github/workflows/secret-rotation-validator.yml` | CI/CD pipeline: runs the unit tests, then the validator, and publishes a report. |
| `Workflow.Tests.ps1` | Workflow structure tests, an actionlint check, and the `act` acceptance suite. |
| `test/ActHarness.psm1` | Helper that runs one fixture through `act push --rm` in an isolated repo. |
| `act-result.txt` | Captured output of every `act` run (the required artifact). |

## How a secret is classified

For each secret, evaluated against a **reference date** (defaults to today, but
injectable for deterministic runs):

```
expiryDate      = lastRotated + rotationPolicyDays
daysUntilExpiry = expiryDate - referenceDate     (whole days)

daysUntilExpiry < 0                       -> expired
0 <= daysUntilExpiry <= warningWindowDays -> warning
otherwise                                 -> ok
```

A secret expiring *exactly* on the reference date is a `warning` (the policy
interval has not strictly elapsed yet), not `expired`.

## Configuration format

```json
{
  "referenceDate": "2026-06-28",      // optional; overridden by -ReferenceDate
  "warningWindowDays": 14,            // optional; overridden by -WarningWindowDays
  "secrets": [
    {
      "name": "DATABASE_PASSWORD",    // required, non-empty
      "lastRotated": "2026-01-01",    // required, ISO date
      "rotationPolicyDays": 90,       // required, positive integer
      "requiredBy": ["api-gateway"]   // optional metadata
    }
  ]
}
```

Parameter precedence for the window and reference date is:
**explicit parameter → config file → built-in default** (window `14`, date *today*).

## Usage

```powershell
# Markdown report (report-only; always exits 0)
./SecretRotationValidator.ps1 -ConfigPath fixtures/mixed.json

# JSON report
./SecretRotationValidator.ps1 -ConfigPath fixtures/mixed.json -Format json

# CI guardrail: exit non-zero if anything is expired
./SecretRotationValidator.ps1 -ConfigPath fixtures/mixed.json -FailOnExpired

# Override the warning window and write to a file
./SecretRotationValidator.ps1 -ConfigPath fixtures/mixed.json -WarningWindowDays 30 -OutputPath report.md
```

Every parameter also has an environment-variable fallback
(`SECRET_ROTATION_CONFIG`, `SECRET_ROTATION_WARNING_DAYS`,
`SECRET_ROTATION_REFERENCE_DATE`, `SECRET_ROTATION_FORMAT`,
`SECRET_ROTATION_FAIL_ON_EXPIRED`).

Exit codes: `0` (ok / report-only), `1` (`-FailOnExpired` and a secret is
expired), `2` (a usage or configuration error, with a clear message).

## Testing

```powershell
# Unit tests (fast)
Invoke-Pester ./SecretRotationValidator.Tests.ps1

# Workflow structure + actionlint only (instant, no Docker)
Invoke-Pester ./Workflow.Tests.ps1 -ExcludeTagFilter Act

# Full acceptance: runs the pipeline through `act` for all three fixtures
# (writes act-result.txt) and asserts the exact report values.
Invoke-Pester ./Workflow.Tests.ps1
```

The pipeline runs the unit suite **inside** the container, so every test case is
also exercised through the GitHub Actions workflow itself.

## The pipeline

`secret-rotation-validator.yml` triggers on push, pull request, a weekly cron
schedule, and manual dispatch (with `config_path` / `warning_window_days` /
`format` inputs). It uses least-privilege `contents: read` permissions and two
dependent jobs:

1. **unit-tests** — checks out the repo and runs the Pester suite.
2. **rotation-report** (`needs: unit-tests`) — runs the validator against the
   configured inventory, prints the Markdown and JSON reports plus machine-
   readable markers, and publishes the report to the job summary.
