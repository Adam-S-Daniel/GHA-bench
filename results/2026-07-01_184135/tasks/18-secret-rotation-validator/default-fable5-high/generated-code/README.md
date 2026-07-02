# Secret Rotation Validator

Reads a JSON config of secrets (name, last-rotated date, rotation policy in
days, required-by services — all mock data), classifies each secret as
**expired**, **warning** (due within a configurable window), or **ok**, and
emits a rotation report with notifications grouped by urgency, as a markdown
table or JSON.

## Usage

```bash
python3 secret_rotation_validator.py --config fixtures/secrets.json \
    [--as-of 2026-07-01] [--warn-days 14] [--format markdown|json]
```

- `--as-of` defaults to today; tests always pass it explicitly (or mock the
  injectable `_today()` clock) so results are deterministic.
- Exit codes: `0` report produced, `1` config/usage error with a meaningful
  message on stderr (never a traceback).

## Classification rules

`due_date = last_rotated + rotation_days`, `days_remaining = due_date - as_of`.

| Condition | Status |
| --- | --- |
| `days_remaining <= 0` (due today or past) | expired |
| `0 < days_remaining <= warn_days` (boundary inclusive) | warning |
| otherwise | ok |

Within each group, secrets sort most-urgent first (fewest days remaining).

## Layout

- `secret_rotation_validator.py` — library (`load_config`, `classify_secret`,
  `build_report`, `render_report`) + CLI. Pure stdlib, Python 3.9+.
- `tests/test_secret_rotation_validator.py` — 32 unit tests, built strictly
  red/green TDD (one failing test group at a time, then minimal code, then
  refactor). Uses fixture files (`tests/fixtures/`), a fixture factory, and a
  mocked clock.
- `tests/test_workflow_structure.py` — host-side workflow checks: YAML shape,
  triggers/jobs/steps, referenced paths exist, actionlint exit code 0.
- `fixtures/` — CI fixture data: `secrets.json` (default case), `case.env`
  (deterministic `AS_OF`/`WARN_DAYS` for CI), `invalid.json` (error-handling
  probe).
- `.github/workflows/secret-rotation-validator.yml` — CI pipeline: `test` job
  (unit suite) → `validate` job (markdown + JSON reports, summary line,
  graceful-failure check).
- `run_act_tests.py` — end-to-end harness. Every test case runs through the
  workflow via `act push --rm` in an isolated temp git repo with that case's
  fixture data; output is appended to `act-result.txt` and asserted against
  exact expected values (table rows, summary counts, notification text) plus
  "Job succeeded" for every job.

## Running the tests

```bash
python3 run_act_tests.py     # structure tests + all cases through act (Docker)
```

`act-result.txt` holds the delimited output and PASS/FAIL verdict per case.
