# Secret Rotation Validator

A PowerShell tool that evaluates secret-rotation health from mock metadata,
classifies each secret by urgency (**expired** / **warning** / **ok**), and
emits a grouped rotation report as a **markdown table** or **JSON**. Built
red/green TDD with Pester, and wired into a real GitHub Actions pipeline that
is exercised end-to-end with [`act`](https://github.com/nektos/act).

## Files

| File | Purpose |
| ---- | ------- |
| `SecretRotationValidator.psm1` | Core module: classification, aggregation, formatting, config loading. |
| `Invoke-Validator.ps1` | CLI entrypoint used by the workflow. Reads config, prints report, optional CI gate. |
| `SecretRotationValidator.Tests.ps1` | Pester unit tests (TDD red/green). |
| `WorkflowStructure.Tests.ps1` | Pester static checks of the workflow YAML + actionlint. |
| `Run-ActTests.ps1` | End-to-end harness: runs the workflow through `act` for each fixture and asserts exact output. |
| `fixtures/secrets.json` | Default mock secret configuration. |
| `.github/workflows/secret-rotation-validator.yml` | CI/CD pipeline. |
| `act-result.txt` | Captured `act` output for every test case (generated artifact). |

## Secret metadata

Each secret is an object with:

```json
{ "name": "db-password", "lastRotated": "2026-01-01", "policyDays": 30, "requiredBy": ["api", "worker"] }
```

The config file may be a bare JSON array or an object with a top-level
`secrets` array.

## Urgency rules

Given `dueDate = lastRotated + policyDays` and `daysUntilDue = dueDate - referenceDate`:

* **expired** — `daysUntilDue < 0`
* **warning** — `0 <= daysUntilDue <= warningDays`
* **ok** — due beyond the warning window

## Usage

```powershell
# Markdown report (default)
./Invoke-Validator.ps1 -ConfigPath fixtures/secrets.json -WarningDays 14

# JSON report
./Invoke-Validator.ps1 -ConfigPath fixtures/secrets.json -Format json

# CI gate: exit 2 if any secret is expired
./Invoke-Validator.ps1 -ConfigPath fixtures/secrets.json -FailOnExpired

# Pin "now" for deterministic output
./Invoke-Validator.ps1 -ConfigPath fixtures/secrets.json -ReferenceDate 2026-06-27
```

Config, warning window, format and reference date also read from the
`SECRETS_CONFIG`, `WARNING_DAYS`, `OUTPUT_FORMAT` and `REFERENCE_DATE`
environment variables (CLI parameters take precedence).

## Testing

```powershell
# Unit + structure tests
Invoke-Pester -Path .

# Full end-to-end pipeline through act (writes act-result.txt)
pwsh -File ./Run-ActTests.ps1
```

The GitHub Actions workflow runs the Pester suite (`unit-tests` job) and then
generates the rotation report (`validate` job, which `needs: unit-tests`).
