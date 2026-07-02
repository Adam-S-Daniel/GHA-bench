# Secret Rotation Validator

Validates a mock secrets configuration against per-secret rotation policies,
flags secrets that are **expired** or **expiring soon** (configurable warning
window), and emits a rotation report with notifications grouped by urgency —
as a markdown table or JSON. TypeScript on Bun, built test-first (red/green
TDD).

## Usage

```bash
bun run src/cli.ts --config secrets.json                 # markdown, 14-day window
bun run src/cli.ts --config secrets.json --format json   # machine-readable
bun run src/cli.ts --config secrets.json --window 30     # custom warning window
bun run src/cli.ts --config secrets.json --now 2026-07-02  # pin the reference date (CI reproducibility)
```

Config format (see `fixtures/`):

```json
[
  {
    "name": "db-password",
    "lastRotated": "2026-01-01",
    "rotationPolicyDays": 90,
    "requiredBy": ["auth-service", "billing-api"]
  }
]
```

## Classification rules

A secret expires on `lastRotated + rotationPolicyDays` (UTC day math, so
results are timezone-independent):

| Urgency   | Condition                                   |
| --------- | ------------------------------------------- |
| `expired` | due today or overdue (`daysUntilExpiry <= 0`) |
| `warning` | `0 < daysUntilExpiry <= warningWindowDays`  |
| `ok`      | expires after the warning window            |

Within each bucket, secrets are ordered most-urgent first (ties broken by
name) so the output is fully deterministic.

Errors (malformed JSON, impossible dates, non-positive policies, bad flags)
exit 1 with a message naming the offending entry and field.

## Layout

- `src/validator.ts` — date math + urgency classification
- `src/config.ts` — config parsing/validation with pinpointed errors
- `src/report.ts` — grouped report generation
- `src/format.ts` — markdown/JSON formatters
- `src/cli.ts` — argument parsing and I/O
- `tests/` — bun test suite (unit, CLI integration, workflow structure)
- `fixtures/` — mock secret configs (mixed, all-ok, invalid)

## Testing

```bash
bun test                          # full suite (46 tests)
actionlint .github/workflows/secret-rotation-validator.yml
bun run scripts/run-act-tests.ts  # end-to-end: every case through act
```

The CI pipeline (`.github/workflows/secret-rotation-validator.yml`) runs on
push / PR / weekly schedule / manual dispatch with two jobs: `test` (full bun
test suite) and `report` (needs `test`; generates both report formats from
`$SECRETS_FILE` and verifies the CLI fails gracefully on an invalid config).
`REFERENCE_DATE` pins the evaluation date so CI output is reproducible.

`scripts/run-act-tests.ts` executes every pipeline test case through
`act push --rm` in an isolated temp git repo (project files + that case's
fixture as `secrets.json`), appends all output to `act-result.txt`, and
asserts act exit code 0, both jobs succeeded, and exact expected values
(specific table rows and JSON summary counts).
