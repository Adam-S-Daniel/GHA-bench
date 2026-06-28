# Secret Rotation Validator (PowerShell)

Identifies secrets that are **expired** or **expiring soon** based on each
secret's last-rotated date and rotation policy, then produces a rotation report
and notifications **grouped by urgency** (`expired` / `warning` / `ok`) in either
**markdown** or **JSON** format.

All input is mock metadata — no real secret material is ever read.

## Files

| File | Purpose |
| --- | --- |
| `SecretRotation.psm1` | Core library: status classification, report building, markdown/JSON rendering, config loading + validation. |
| `Invoke-SecretRotationValidator.ps1` | CLI entry point: loads a config, builds a report, prints it, and emits a machine-parseable `RESULT` line. |
| `fixtures/*.json` | Test fixtures (`healthy`, `mixed`, `all-expired`) with a fixed `asOf` date for deterministic results. |
| `tests/SecretRotation.Tests.ps1` | Pester unit tests for the core logic (written test-first, red/green TDD). |
| `tests/Workflow.Tests.ps1` | Workflow structure tests, `actionlint` assertion, and the end-to-end `act` integration harness. |
| `.github/workflows/secret-rotation-validator.yml` | CI/CD pipeline that runs the validator over every fixture in Docker. |

## Classification rule

Relative to a reference **as-of** date (deterministic; defaults to today):

```
daysUntilExpiry  = (lastRotated + rotationPolicyDays) - asOf      # whole days
daysUntilExpiry < 0                        -> expired
0 <= daysUntilExpiry <= warningWindowDays  -> warning   (expires today counts here)
daysUntilExpiry > warningWindowDays        -> ok
```

The warning window is configurable: CLI `-WarningWindowDays` overrides the config
file's `warningWindowDays`, which falls back to a 30-day default.

## Configuration format

```json
{
  "warningWindowDays": 14,
  "asOf": "2025-06-01",
  "secrets": [
    { "name": "DB_PASSWORD", "lastRotated": "2025-01-01", "rotationPolicyDays": 90, "requiredBy": ["api", "worker"] }
  ]
}
```

`asOf` is optional (used for reproducible reports/tests). `requiredBy` is optional.

## CLI usage

```pwsh
# Markdown report (default) for a fixture
./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/mixed.json

# JSON report, with a custom warning window
./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/mixed.json -Format json -WarningWindowDays 30

# Fail the process (exit 1) if any secret is expired — useful for CI gating
./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/mixed.json -FailOnExpired
```

Exit codes: `0` success · `1` `-FailOnExpired` triggered · `2` usage/input error.

Every run prints a stable summary line for easy parsing:

```
RESULT fixture=mixed expired=2 warning=2 ok=1 total=5
```

## Running the tests

```pwsh
Invoke-Pester -Path ./tests
```

- Unit tests run directly and are fast.
- The `Act`-tagged tests run the **whole GitHub Actions workflow in Docker** via
  `act push`, save the transcript to `act-result.txt`, and assert exact expected
  values per fixture. Run only the fast checks with
  `Invoke-Pester ./tests/Workflow.Tests.ps1 -Tag Structure`.

## CI/CD workflow

`.github/workflows/secret-rotation-validator.yml` triggers on `push`,
`pull_request`, a weekly `schedule`, and `workflow_dispatch` (with `format` and
`warning_window` inputs). The `validate` job runs as a **matrix over every
fixture**, rendering both markdown (to the job summary) and JSON; the `report`
job **depends on** `validate`. Permissions are least-privilege (`contents: read`).
PowerShell steps use `shell: pwsh`.

> Note: the workflow does not pass `-FailOnExpired`, so the pipeline reports
> rotation status without failing the build (and `act` exits 0). Add the switch
> in a step to turn the validator into a hard CI gate.
