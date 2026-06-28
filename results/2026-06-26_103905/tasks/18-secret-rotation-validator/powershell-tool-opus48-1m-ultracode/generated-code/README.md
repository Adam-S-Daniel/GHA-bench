# Secret Rotation Validator

A PowerShell tool that reads a configuration of secrets with rotation metadata,
identifies secrets that are **expired** or **expiring** within a configurable
warning window, and produces a rotation report grouped by urgency
(**expired / warning / ok**) in **Markdown** or **JSON**. It ships with a
GitHub Actions workflow that runs the validator (and its unit tests) in CI.

Built with red/green TDD using Pester. Every functional test case is also
exercised end-to-end through the real workflow via [`act`](https://github.com/nektos/act).

## Files

| File | Purpose |
| --- | --- |
| `SecretRotationValidator.psm1` | Core library: pure, testable evaluation logic. |
| `secret-rotation-validator.ps1` | CLI entry point invoked by the workflow. |
| `secrets.json` | Default sample configuration (sensible default for a plain run). |
| `fixtures/*.json` | Test-case configurations (also fed through `act`). |
| `tests/SecretRotationValidator.Tests.ps1` | TDD unit tests for the library + CLI logic. |
| `tests/Workflow.Tests.ps1` | Workflow structure / file-reference / actionlint tests. |
| `tests/ActIntegration.Tests.ps1` | End-to-end tests that run the workflow through `act`. |
| `Run-ActTests.ps1` | Convenience wrapper to run the act integration suite. |
| `.github/workflows/secret-rotation-validator.yml` | The CI/CD pipeline. |
| `act-result.txt` | Captured `act` output for every test case (generated artifact). |

## Configuration schema

```jsonc
{
  "referenceDate": "2026-06-28",   // optional "today"; defaults to the current date
  "warningDays": 14,               // optional warning window; defaults to 14
  "secrets": [
    {
      "name": "db-password",
      "lastRotated": "2026-01-01",       // yyyy-MM-dd
      "rotationPolicyDays": 90,          // rotate every N days
      "requiredBy": ["api", "worker"]    // optional list of dependent services
    }
  ]
}
```

## Status rules

Let `daysUntilExpiry = rotationPolicyDays - daysSinceRotation`:

| Status | Condition |
| --- | --- |
| **Expired** | `daysUntilExpiry <= 0` (due now or overdue) |
| **Warning** | `0 < daysUntilExpiry <= warningDays` |
| **Ok** | `daysUntilExpiry > warningDays` |

Within each urgency group, secrets are sorted most-overdue first, then by name,
for deterministic output.

## Usage

```powershell
# Markdown report (default) from the default config
./secret-rotation-validator.ps1 -Format Markdown

# JSON report from a specific config
./secret-rotation-validator.ps1 -ConfigPath fixtures/case1-mixed.json -Format Json

# Machine-readable summary, overriding the warning window
./secret-rotation-validator.ps1 -Format Summary -WarningDays 30

# Use as a CI gate: exit 1 if anything is expired
./secret-rotation-validator.ps1 -FailOnExpired
```

Precedence for the reference date and warning window is
**parameter > config file > built-in default**.

### Output formats

* **Markdown** - one table per urgency group plus a summary, suitable for a
  GitHub Actions job summary.
* **Json** - a structured `{ referenceDate, warningDays, summary, groups }`
  document (camelCase) for downstream tooling.
* **Summary** - a grep-friendly contract used by the CI assertions:

  ```
  ROTATION-SUMMARY expired=1 warning=1 ok=1 total=3
  SECRET name=db-password status=Expired daysSinceRotation=178 daysUntilExpiry=-88 requiredBy=api,worker
  ...
  ```

## Running the tests

```powershell
# Fast: unit + workflow-structure tests only (no Docker)
Invoke-Pester -Path ./tests -ExcludeTagFilter Act

# Everything, including the act end-to-end suite (needs Docker + act; slower)
Invoke-Pester -Path ./tests

# Just the act integration harness (writes act-result.txt)
./Run-ActTests.ps1
```

## CI/CD pipeline

`.github/workflows/secret-rotation-validator.yml` triggers on `push`,
`pull_request`, a weekly `schedule`, and `workflow_dispatch` (with an optional
`warning_days` input). It uses least-privilege `permissions: contents: read`
and two jobs:

1. **test** - runs the Pester unit tests as a quality gate.
2. **report** (`needs: test`) - runs the validator against `secrets.json`
   (path from the `SECRETS_CONFIG_PATH` env var), printing the Summary, writing
   the Markdown report to the job summary, and saving the JSON report (uploaded
   as an artifact on GitHub-hosted runners).

All `run:` steps that touch the script use `shell: pwsh`. The artifact upload is
skipped under `act` (`if: ${{ !env.ACT }}`) since act has no artifact server.
