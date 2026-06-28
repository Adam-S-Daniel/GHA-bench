# Secret Rotation Validator

A PowerShell tool that reads a configuration of secrets (name, last-rotated date,
rotation policy in days, and the services that require each secret), classifies
every secret by urgency, generates a rotation report, and emits notifications
grouped by urgency. It supports two output formats: a Markdown table and JSON.

> All data is **mock** rotation metadata. The tool never reads or handles real
> secret material — it only reasons about *when* secrets were last rotated.

## How a secret is classified

A secret "expires" on `lastRotated + rotationPolicyDays`. Comparing that against a
reference date (`-ReferenceDate`, default = today) yields `daysUntilExpiry`:

| Condition                                   | Status   |
| ------------------------------------------- | -------- |
| `daysUntilExpiry < 0`                        | Expired  |
| `0 <= daysUntilExpiry <= WarningDays`        | Warning  |
| `daysUntilExpiry > WarningDays`              | OK       |

The warning window (`-WarningDays`, default 14) is configurable.

## Layout

| Path                                   | Purpose                                                   |
| -------------------------------------- | --------------------------------------------------------- |
| `src/SecretRotation.psm1`              | Module with all logic (status, config load, report, format, notify) |
| `Invoke-SecretRotationValidator.ps1`   | CLI entry point used by the workflow                       |
| `tests/SecretRotation.Tests.ps1`       | Pester unit tests (TDD) — 40 tests                         |
| `meta-tests/Workflow.Tests.ps1`        | Pester workflow-structure tests — 18 tests                |
| `fixtures/secrets.json`                | Default config the workflow reads                         |
| `fixtures/cases/*.json`                | Per-scenario fixtures (mixed / all-ok / all-expired)      |
| `.github/workflows/secret-rotation-validator.yml` | CI pipeline (test job → validate job)          |
| `Run-ActTests.ps1`                     | End-to-end harness that runs everything through `act`     |
| `act-result.txt`                       | Captured `act` output for every test case (artifact)     |

## Usage

```pwsh
# Markdown report (default), warning window of 14 days, fixed reference date
./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/secrets.json `
    -WarningDays 14 -ReferenceDate 2026-06-28 -Format markdown

# JSON report, also written to a file
./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/secrets.json `
    -Format json -OutFile report.json

# Gate a real CI build: exit code 2 if any secret is expired
./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/secrets.json -FailOnExpired
```

The CLI always prints (regardless of format):

```
SUMMARY expired=1 warning=1 ok=1 total=3
NOTIFY EXPIRED legacy-db-password overdue=88 requiredBy=billing-api,reports-worker
NOTIFY WARNING payments-api-key days=2 requiredBy=payments-gateway
NOTIFY OK session-cache-secret days=63 requiredBy=web-frontend
```

followed by the chosen report wrapped in `<<<REPORT FORMAT=...>>> ... <<<END REPORT>>>`.

**Exit codes:** `0` success · `1` configuration/IO error · `2` expired secrets found
while `-FailOnExpired` was set.

## Development approach (red/green TDD)

Every function was built test-first with Pester: write a failing test, write the
minimum code to pass it, then refactor. The module exposes:

- `Get-SecretStatus` — pure date classification
- `Import-SecretConfig` — load + validate JSON config (clear errors)
- `Get-RotationReport` — group secrets into Expired/Warning/OK with a summary
- `Format-RotationReport` — render Markdown or JSON
- `Get-RotationNotification` — per-secret notification lines

## Testing

```pwsh
# Unit tests (the suite the CI test job runs)
Invoke-Pester -Path ./tests

# Workflow-structure tests (host-side: need actionlint + powershell-yaml)
Invoke-Pester -Path ./meta-tests
```

## CI pipeline

`.github/workflows/secret-rotation-validator.yml` runs on push, pull_request, a
weekly schedule, and manual dispatch. It has two jobs:

1. **test** — runs the Pester suite inside the runner (`shell: pwsh`).
2. **validate** (`needs: test`) — runs the validator against the config and
   produces both Markdown and JSON reports, attaching the Markdown to the job
   summary.

`REFERENCE_DATE` is pinned in the workflow so reports are deterministic.

## End-to-end testing through `act`

`Run-ActTests.ps1` exercises the pipeline exactly as GitHub would, using
[`act`](https://github.com/nektos/act). For each fixture case it builds an
isolated temp git repo, overlays that case's fixture onto `fixtures/secrets.json`,
runs `act push --rm`, appends the output to `act-result.txt`, and asserts:

- `act` exited `0`,
- every job shows `Job succeeded`,
- the output contains the **exact** expected SUMMARY / NOTIFY / report values.

```pwsh
pwsh -File ./Run-ActTests.ps1            # all cases, fresh act-result.txt
```
