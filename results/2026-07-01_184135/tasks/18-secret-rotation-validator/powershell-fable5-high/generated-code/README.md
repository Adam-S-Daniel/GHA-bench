# Secret Rotation Validator

PowerShell tool that classifies secrets (mock metadata: name, last-rotated
date, rotation policy in days, required-by services) as **Expired**,
**Warning**, or **OK** against a configurable warning window, and renders the
grouped report as a markdown table or JSON. Built test-first with Pester.

## Layout

| Path | Purpose |
| --- | --- |
| `src/SecretRotationValidator.psm1` | Module: `Get-SecretRotationStatus`, `Import-SecretConfig`, `Get-RotationReport`, `Format-RotationReport` |
| `Invoke-SecretRotationValidator.ps1` | CLI entry point (exit 0 ok, 1 error, 2 with `-FailOnExpired`) |
| `fixtures/secrets.json` | Mock secrets config used by the unit tests |
| `fixtures/ci-case.json` | Config the CI report job reads (swapped per case by the act harness) |
| `tests/SecretRotationValidator.Tests.ps1` | Unit + CLI tests (TDD cycles 1–5) |
| `tests/Workflow.Tests.ps1` | Workflow structure tests + actionlint gate |
| `.github/workflows/secret-rotation-validator.yml` | CI pipeline (Pester job → report job) |
| `Run-ActTests.ps1` | End-to-end harness: runs each test case through `act push`, writes `act-result.txt` |
| `act-result.txt` | Captured act output + exact-value assertion results |

## Usage

```powershell
# All tests
Invoke-Pester -Path ./tests

# Generate a report
./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/secrets.json -Format Markdown
./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/secrets.json -Format Json -WarningWindowDays 30

# Gate a pipeline on expired secrets (exit code 2 when any are expired)
./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/secrets.json -FailOnExpired

# Run every test case through the GitHub Actions workflow via act
./Run-ActTests.ps1            # full run (invokes act per case)
./Run-ActTests.ps1 -Replay    # re-assert against saved act output
```

The classification rule: `expiry = lastRotated + rotationPolicyDays`;
negative days-until-expiry ⇒ Expired, within the warning window ⇒ Warning,
otherwise OK. The workflow pins `AS_OF_DATE` so CI output is deterministic.
