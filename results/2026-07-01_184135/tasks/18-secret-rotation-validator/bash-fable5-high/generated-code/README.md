# Secret Rotation Validator

Validates a JSON config of secrets (name, last-rotated date, rotation policy
in days, required-by services — mock data) against a reference date and
reports which secrets are **expired**, **expiring within a warning window**,
or **ok**, in markdown or JSON.

## Usage

```bash
./secret-rotation-validator.sh --config config/secrets.json \
    [--warn-days 14] [--now YYYY-MM-DD] [--format markdown|json]
```

- A secret is **expired** when `last_rotated + rotation_days <= now`
  (the expiry day itself counts as expired).
- It is a **warning** when it expires within `--warn-days` (default 14).
- `--now` pins the reference date for deterministic runs; defaults to today (UTC).
- Exit codes: `0` success, `2` usage/config error.

Config shape (see `config/secrets.json`):

```json
{ "secrets": [ { "name": "db-password", "last_rotated": "2026-03-01",
                 "rotation_days": 90, "required_by": ["billing-api"] } ] }
```

## Tests

Built red/green TDD; the suite covers CLI errors, classification (including
day-exact boundaries), both output formats, config validation, and the CI
workflow structure.

```bash
bats tests/            # 31 tests: script behaviour + workflow structure
./run-act-tests.sh     # every test case end-to-end through the GitHub Actions
                       # workflow via act; writes act-result.txt
```

## CI

`.github/workflows/secret-rotation-validator.yml` runs on push, PR, a weekly
schedule, and manual dispatch: a `test` job runs the full bats suite, then a
`report` job generates the markdown report (into the step summary) plus JSON
and per-secret `NOTIFY[urgency]` lines. `REFERENCE_DATE` is pinned so output
on the mock data is deterministic; `WARN_DAYS` is overridable via dispatch
input.
