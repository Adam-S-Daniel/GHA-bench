# Secret Rotation Validator (PowerShell)

Evaluates a set of secrets (name, last-rotated date, rotation policy in days,
required-by services) against a reference date and a configurable warning
window, classifies each secret by urgency (`expired` / `warning` / `ok`),
and renders a rotation report as a **markdown table** or **JSON**.

## Layout

| Path | Purpose |
| --- | --- |
| `src/SecretRotationValidator.psm1` | Core module: classification, report, formatting, config loading |
| `Invoke-SecretRotationValidator.ps1` | CLI entry point used by the CI pipeline |
| `fixtures/secrets.json` | Default mock secrets config |
| `fixtures/cases/*.json` | Per-test-case fixtures with known-good outputs |
| `tests/SecretRotationValidator.Tests.ps1` | Pester unit tests (TDD) |
| `tests/Workflow.Tests.ps1` | Workflow structure tests + end-to-end `act` harness |
| `.github/workflows/secret-rotation-validator.yml` | GitHub Actions pipeline |
| `act-result.txt` | Captured `act` output for every end-to-end case |

## Classification rule

For each secret: `dueDate = lastRotated + rotationPolicyDays`, and
`daysUntilDue = dueDate - referenceDate`.

* `daysUntilDue < 0` → **expired**
* `0 <= daysUntilDue <= warningWindowDays` → **warning**
* otherwise → **ok**

The reference date is always supplied explicitly (never read from the clock),
keeping the logic pure and deterministic for testing.

## Run locally

```powershell
# Unit tests (red/green TDD)
Invoke-Pester -Path tests/SecretRotationValidator.Tests.ps1

# Generate a report
./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/secrets.json `
    -ReferenceDate 2026-06-01 -WarningWindowDays 14 -Format markdown
```

## CI pipeline

`.github/workflows/secret-rotation-validator.yml` runs on push, pull_request,
a daily schedule, and manual dispatch. It has two jobs:

1. **unit-tests** — runs the Pester unit suite.
2. **validate-rotation** — `needs: unit-tests`; runs the validator against the
   committed config and prints the report.

Settings flow as `dispatch input → injected env (REFERENCE_DATE etc.) → default`,
so the local `act` harness drives deterministic runs by passing `--env`.

## End-to-end testing through `act`

`tests/Workflow.Tests.ps1` builds an isolated git repo per case, runs
`act push --rm` against the workflow, appends output to `act-result.txt`, and
asserts on exact expected values (exit code 0, both jobs succeeded, exact
urgency counts and per-secret rows).
