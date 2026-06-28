# Secret Rotation Validator

Validates a configuration of secrets against their rotation policies, classifies
each by urgency (**expired / warning / ok**), and emits a rotation report as a
**markdown table**, **JSON**, or a compact **summary** line.

## Layout

| Path | Purpose |
| --- | --- |
| `secret_rotation_validator.py` | The validator (pure functions + a CLI). |
| `tests/test_validator.py` | Unit tests for the logic (written red→green TDD). |
| `tests/test_workflow.py` | Workflow structure tests **and** the `act` pipeline integration test. |
| `fixtures/*.json` | Mock secret configs (one per test case + the workflow default). |
| `.github/workflows/secret-rotation-validator.yml` | CI workflow that runs the validator. |
| `act-result.txt` | Captured output of every test case run through `act` (a required artifact). |

## How classification works

For each secret, `expiry_date = last_rotated + rotation_policy_days`, then
`days_until_expiry = expiry_date - now`:

* `days_until_expiry < 0` → **expired**
* `0 ≤ days_until_expiry ≤ warning_days` → **warning** (window is inclusive)
* otherwise → **ok**

The reference date (`now`) is always injected (via `--now` / the `NOW_DATE`
environment variable), never read from the wall clock, so both the tests and the
CI workflow are fully deterministic.

## Usage

```bash
# Markdown report (default format)
python3 secret_rotation_validator.py --config fixtures/mixed.json --now 2026-06-27

# JSON, custom warning window
python3 secret_rotation_validator.py --config fixtures/mixed.json --warning-days 30 --format json

# Compact summary line; fail the process if anything is already expired (for CI)
python3 secret_rotation_validator.py --config fixtures/mixed.json --format summary --fail-on expired
```

`--now` defaults to today. By default the process always exits `0`; pass
`--fail-on warning|expired` to make a scheduled CI run surface a non-zero exit.

## Testing

```bash
python3 -m pytest tests/ -v
```

The suite covers (a) unit tests of the classification/report/render logic, and
(b) the GitHub Actions workflow — its structure, `actionlint` cleanliness, and a
real end-to-end run of all three fixtures through the pipeline via `act`
(nektos/act), with output captured to `act-result.txt`.
