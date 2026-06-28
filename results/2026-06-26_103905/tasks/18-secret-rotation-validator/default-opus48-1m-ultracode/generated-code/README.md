# Secret Rotation Validator

Given a configuration of secrets with metadata (name, last-rotated date,
rotation policy in days, required-by services), this tool finds secrets that are
**expired** or **expiring within a configurable warning window**, generates a
rotation report, and emits notifications grouped by urgency — in **markdown** or
**JSON**.

The script (`secret_rotation_validator.py`) uses **only the Python standard
library**, so it runs unchanged on a vanilla CI runner.

## Urgency model

A secret expires `rotation_policy_days` after its `last_rotated` date.

| Bucket    | Condition                                              |
|-----------|--------------------------------------------------------|
| `expired` | expiry date is already in the past                     |
| `warning` | expires today, or within the next `warning_days` days  |
| `ok`      | expires further out than the warning window            |

## Config format

```json
{
  "warning_days": 14,
  "now": "2026-06-28",
  "format": "markdown",
  "secrets": [
    {
      "name": "DB_PASSWORD",
      "last_rotated": "2026-01-01",
      "rotation_policy_days": 90,
      "required_by": ["billing-api", "worker"]
    }
  ]
}
```

`warning_days`, `now`, and `format` are optional defaults (handy for reproducible
runs/tests). CLI flags override them. `now` defaults to the real today when
omitted. `required_by` defaults to an empty list.

## Usage

```bash
# Markdown report (default)
python3 secret_rotation_validator.py --config fixtures/secrets.json

# JSON report, custom warning window, fixed reference date
python3 secret_rotation_validator.py --config fixtures/secrets.json \
    --format json --warning-days 30 --now 2026-06-28

# One-line summary, and fail the build (exit 3) if anything is expired
python3 secret_rotation_validator.py --config fixtures/secrets.json \
    --format summary --fail-on expired
```

Exit codes: `0` success · `2` configuration error · `3` `--fail-on` gate tripped.

## Tests (red/green TDD)

* `tests/unit/` — fast unit tests for the script logic (run inside the CI
  pipeline via the workflow's `unit-tests` job).
* `tests/integration/test_workflow_structure.py` — parses the workflow YAML,
  checks its structure, verifies referenced paths exist, and asserts
  `actionlint` passes.
* `tests/integration/test_act_pipeline.py` — runs the **real** workflow through
  `act` (Docker) for three fixture cases, appends each run's output to
  `act-result.txt`, and asserts exact expected report values.

```bash
python3 -m pytest tests/unit                              # fast
python3 -m pytest tests/integration/test_workflow_structure.py
python3 -m pytest tests/integration/test_act_pipeline.py  # slow; needs act+docker
```

## CI workflow

`.github/workflows/secret-rotation-validator.yml` runs on push, pull_request, a
weekly schedule, and `workflow_dispatch` (with `config_file` / `warning_days` /
`format` inputs). It runs the unit tests, then generates the report into the job
summary and a `rotation-report.json` artifact.
