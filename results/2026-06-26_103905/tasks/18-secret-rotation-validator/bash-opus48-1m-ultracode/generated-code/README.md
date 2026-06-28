# Secret Rotation Validator

A small Bash tool that checks a set of secrets against their rotation policies and
reports which ones are **expired**, **expiring soon** (within a configurable
warning window), or **ok** — grouped by urgency, in either a Markdown table or
JSON.

All secret data is mock data supplied via a JSON config; the tool performs no
network calls and touches no real secret material.

## Files

| Path | Purpose |
|------|---------|
| `secret-rotation-validator.sh` | The validator (pure Bash + `jq`). |
| `tests/validator.bats` | 30 unit tests (TDD red/green). Run inside CI. |
| `tests/workflow_structure.bats` | 16 tests that parse the workflow YAML and assert its structure + that it passes `actionlint`. |
| `act-tests/integration_act.bats` | Integration harness: runs the workflow end-to-end through `act` for three fixtures and asserts exact output. Produces `act-result.txt`. |
| `fixtures/*.json` | Mock secret configs used by the tests and the workflow. |
| `.github/workflows/secret-rotation-validator.yml` | CI/CD pipeline that lints + unit-tests the script and generates a rotation report. |
| `act-result.txt` | Captured `act` output for every integration case (required artifact). |

## Usage

```bash
# Markdown report (default), using "today" as the reference date
./secret-rotation-validator.sh fixtures/secrets.json

# JSON report with a 30-day warning window and a pinned reference date
./secret-rotation-validator.sh --format json --warn-days 30 --now 2026-06-28 fixtures/secrets.json

# Read config from stdin
cat fixtures/secrets.json | ./secret-rotation-validator.sh -

# Use as a hard CI gate: non-zero exit if anything is expired
./secret-rotation-validator.sh --fail-on-expired fixtures/secrets.json
```

### Config format

```json
{
  "secrets": [
    {
      "name": "db-password",
      "last_rotated": "2026-01-01",
      "rotation_policy_days": 90,
      "required_by": ["api-service", "worker"]
    }
  ]
}
```

### Classification rules

For each secret, `days_until_due = rotation_policy_days - age_in_days`:

- `days_until_due < 0` → **expired** (overdue; reported as a negative number)
- `0 <= days_until_due <= warn-days` → **warning** (due within the window)
- `days_until_due > warn-days` → **ok**

Date math is done in UTC (`TZ=UTC`) on midnight epoch seconds so results are
deterministic regardless of host timezone/DST. `--now` pins the reference date
for reproducible output (the tests rely on this).

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success (report produced). |
| `2` | Usage/runtime error (bad args, missing file, invalid JSON, bad date). |
| `3` | `--fail-on-expired` was set and at least one secret is expired. |

## Development approach (TDD)

Built red/green: each behavior started as a failing `bats` test exercising the
CLI, followed by the minimum implementation to make it pass. The same CLI surface
is what the GitHub Actions workflow consumes, so the unit tests verify the tool
the way it is actually used.

## Testing

```bash
# Fast, dependency-light: unit + workflow-structure tests
bats tests/

# Static checks
bash -n secret-rotation-validator.sh
shellcheck secret-rotation-validator.sh
actionlint .github/workflows/secret-rotation-validator.yml

# Full pipeline integration through act (slow; needs Docker + act).
# Runs the workflow for three fixtures and writes act-result.txt.
bats act-tests/integration_act.bats
```

### How the pipeline is tested

The workflow has two dependent jobs:

1. **lint-and-test** — installs `bats`/`shellcheck` if missing, runs `bash -n`,
   `shellcheck`, and the bats unit suite.
2. **rotation-report** (`needs: lint-and-test`) — runs the validator on
   `fixtures/secrets.json`, emitting a Markdown report (also to the job summary),
   a JSON report, and a single machine-readable `ROTATION-SUMMARY ...` line.

`act-tests/integration_act.bats` builds a throwaway git repo per case, drops that
case's fixture in as `fixtures/secrets.json`, runs `act push --rm`, appends the
output to `act-result.txt`, and asserts: act exited 0, both jobs report
`Job succeeded`, and the report contains the exact expected counts/rows for that
input.
