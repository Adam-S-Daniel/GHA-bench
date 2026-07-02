# Secret Rotation Validator

Bash tool that reads a JSON config of secrets (name, last-rotated date,
rotation policy in days, required-by services), classifies each as
**expired / warning / ok** against a configurable warning window, and emits
a rotation report in markdown or JSON. Built with red/green TDD using
bats-core.

## Usage

```bash
./secret-rotation-validator.sh \
  --config fixtures/secrets.json \
  --warning-days 14 \
  --format markdown \        # or: json
  --now 2026-07-01           # optional; defaults to today (UTC)
```

Classification: `days_left <= 0` → expired, `days_left <= warning-days` →
warning, otherwise ok. All date math is at UTC midnight; `--now` makes
results deterministic for tests.

## Layout

| Path | Purpose |
|------|---------|
| `secret-rotation-validator.sh` | The validator |
| `tests/secret_rotation_validator.bats` | Unit/functional tests (16) |
| `tests/workflow_structure.bats` | Workflow structure tests (6) |
| `tests/fixtures/` | Unit-test fixture configs |
| `fixtures/secrets.json`, `fixtures/params.env` | Default data/params the workflow runs against |
| `act-fixtures/case-*/` | Per-case fixture data for the act harness |
| `.github/workflows/secret-rotation-validator.yml` | CI pipeline (lint + bats, then report generation) |
| `run-act-tests.sh` | Runs every case through the workflow via `act push`, asserts exact outputs, writes `act-result.txt` |

## Running the tests

```bash
bats tests/            # unit + workflow-structure tests (host)
./run-act-tests.sh     # full pipeline via nektos/act (3 runs, needs Docker)
```
