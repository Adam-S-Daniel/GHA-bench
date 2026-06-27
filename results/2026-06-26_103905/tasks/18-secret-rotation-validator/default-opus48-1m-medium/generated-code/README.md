# Secret Rotation Validator

Validates a configuration of secrets against their rotation policies, classifies
each by urgency (**expired** / **warning** / **ok**), and emits a report as a
markdown table or JSON.

## Usage

```bash
python3 secret_rotation_validator.py --config fixtures/secrets.json \
  --warning-days 14 --now 2026-06-27 --format markdown
```

| Flag | Default | Description |
| --- | --- | --- |
| `--config` | (required) | Path to the secrets JSON file |
| `--warning-days` | `14` | Days-ahead window that counts as "warning" |
| `--now` | today | Pin "today" (YYYY-MM-DD) for deterministic output |
| `--format` | `markdown` | `markdown` or `json` |
| `--fail-on-expired` | off | Exit code `2` if any secret is expired (CI gating) |

### Config shape

```json
{ "secrets": [
  { "name": "DB_PASSWORD", "last_rotated": "2026-01-01",
    "rotation_policy_days": 90, "required_by": ["api", "worker"] }
]}
```

A secret is **expired** if `last_rotated + rotation_policy_days` is in the past,
**warning** if it falls due within `--warning-days`, otherwise **ok**.

## Classification logic

```
next_rotation = last_rotated + rotation_policy_days
days_left     = next_rotation - now
  days_left < 0                 -> expired
  0 <= days_left <= warn_window -> warning
  else                          -> ok
```

## Tests

Built with red/green TDD. Pure functions (`classify_secret`, `build_report`,
renderers) are unit-tested in isolation; the workflow is checked statically and
end-to-end through `act`.

```bash
python3 -m pytest tests/          # unit + workflow-structure tests
python3 tests/run_act_tests.py    # runs the GitHub Actions workflow in Docker via act
```

`tests/run_act_tests.py` spins up a temp git repo per fixture case, runs
`act push --rm --pull=false`, appends output to `act-result.txt`, and asserts
exit code 0, both jobs `Job succeeded`, and exact per-urgency counts.

## CI

`.github/workflows/secret-rotation-validator.yml` runs the validator on push /
PR / weekly schedule / manual dispatch: a `validate` job generates the report
(written to the job summary + artifacts) and a dependent `gate` job enforces the
rotation policy.
