# Secret Rotation Validator

A Bash tool that reads a JSON configuration of secrets (name, last-rotated date,
rotation policy in days, required-by services — all mock data), classifies each
secret by rotation urgency, and emits a report grouped into **expired**,
**warning**, and **ok**. Output is available as a Markdown table or JSON.

## Usage

```bash
./secret-rotation-validator.sh --config fixtures/secrets.json \
  --warning-days 14 \
  --format markdown        # or: json

# Deterministic evaluation (useful in CI / tests):
./secret-rotation-validator.sh --config fixtures/secrets.json --now 2024-04-01
```

Options:

| Option | Default | Meaning |
| --- | --- | --- |
| `--config FILE` | (required) | JSON array of secret objects |
| `--warning-days N` | `14` | Days before the due date that count as a warning |
| `--format FORMAT` | `markdown` | `markdown` or `json` |
| `--now YYYY-MM-DD` | today (UTC) | Reference "current" date; also `$ROTATION_NOW` |
| `--strict` | off | Exit `2` if any secret is expired |
| `-h`, `--help` | | Show help |

### Classification

```
due_date       = last_rotated + rotation_days
days_remaining = floor(due_date - now)          # negative => overdue
expired : days_remaining < 0
warning : 0 <= days_remaining <= warning_days
ok      : days_remaining > warning_days
```

All date math runs in UTC so DST never causes an off-by-one day.

## Configuration shape

```json
[
  { "name": "db-password", "last_rotated": "2024-01-01", "rotation_days": 90,
    "required_by": ["api", "worker"] }
]
```

## Tests

Built red/green with [bats-core](https://github.com/bats-core/bats-core).

```bash
# Unit + workflow tests
bats test/

# act-based end-to-end workflow run (writes act-result.txt). Run this before
# the act assertions in test/workflow.bats can pass.
bash test/run-act-cases.sh
```

* `test/rotation.bats` — unit tests for the script (classification, grouping,
  formats, strict mode, error handling).
* `test/run-act-cases.sh` — runs `.github/workflows/secret-rotation-validator.yml`
  end-to-end via `act` for three fixtures, captures output to `act-result.txt`.
* `test/workflow.bats` — static workflow-structure tests plus exact-value
  assertions on the captured `act` output.

## CI

`.github/workflows/secret-rotation-validator.yml` runs the validator on `push`,
`pull_request`, a daily `schedule`, and `workflow_dispatch`. The `validate` job
generates the report and exports the per-urgency counts as job outputs; the
`summarize` job (`needs: validate`) prints them and annotates the run when
secrets are expired.
