# Secret Rotation Validator

Reads a configuration of secrets (name, last-rotated date, rotation policy in
days, and the services that require them), flags any that are **expired** or
**expiring** within a configurable warning window, and emits a rotation report
grouped by urgency (`expired` / `warning` / `ok`) in **markdown** or **JSON**.

## Layout

| Path | Purpose |
| --- | --- |
| `secret_rotation_validator.py` | The validator (pure stdlib, importable + CLI). |
| `tests/test_secret_rotation_validator.py` | Unit tests, written test-first (TDD). |
| `fixtures/secrets.json` | Default config the workflow validates. |
| `fixtures/cases/*.json` | Per-case fixtures for the act harness. |
| `.github/workflows/secret-rotation-validator.yml` | CI pipeline that runs the tests + report. |
| `run_act_tests.py` | Harness: runs every case through the workflow via `act`. |
| `test_workflow_structure.py` | Static checks on the workflow (structure + actionlint). |
| `act-result.txt` | Captured `act` output for all cases (generated artifact). |

## Usage

```bash
# Markdown report (default), with a pinned reference date for determinism
python3 secret_rotation_validator.py --config fixtures/secrets.json \
    --warning-days 14 --now 2026-06-28

# JSON report
python3 secret_rotation_validator.py --config fixtures/secrets.json \
    --format json --now 2026-06-28

# Fail the process (exit 2) if anything is already expired -- a CI gate
python3 secret_rotation_validator.py --config fixtures/secrets.json \
    --fail-on-expired
```

Exit codes: `0` success, `1` usage/config error, `2` expired secrets found
(only with `--fail-on-expired`).

### Config format

Either `{"secrets": [...]}` or a bare list. Each secret:

```json
{
  "name": "db-primary-password",
  "last_rotated": "2026-01-01",
  "rotation_policy_days": 90,
  "required_by": ["api", "billing"]
}
```

A secret is `expired` once it is past `last_rotated + rotation_policy_days`,
`warning` if it falls due within the warning window (inclusive of today), and
`ok` otherwise. The "current" date is injectable (`--now`) so every result is
deterministic.

## Development methodology (red/green TDD)

Each behaviour was added as a failing `unittest` test first, then the minimum
code to make it pass: classification -> config loading/validation -> report
grouping -> markdown rendering -> JSON rendering -> the CLI. The suite uses only
the standard library so it runs identically locally and inside CI.

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v   # unit tests
python3 -m unittest test_workflow_structure -v            # workflow structure
```

## CI / running through `act`

The unit tests and the report both run inside the GitHub Actions workflow. The
harness exercises the *real* pipeline for each test case:

```bash
python3 run_act_tests.py        # runs every case through `act push`
```

It builds a throwaway git repo per case (project files + that case's fixture),
runs `act push --rm`, appends the output to `act-result.txt`, then asserts act
exited 0, that every job reported "Job succeeded", and that the parsed report
matches the exact expected counts and per-secret statuses.
