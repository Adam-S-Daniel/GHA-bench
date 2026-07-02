# Secret Rotation Validator

Validates a JSON configuration of secrets (mock data: name, last-rotated date,
rotation policy in days, required-by services) and reports which secrets are
**expired**, in the **warning** window, or **ok** — as a markdown report or
machine-readable JSON with notifications grouped by urgency.

## Usage

```sh
bun run src/cli.ts --config fixtures/secrets.json --warning-days 14 \
  --now 2026-07-01 --format markdown   # or: --format json
```

- `--now` injects the evaluation date so runs are deterministic (defaults to today).
- `--fail-on-expired` exits with code 2 when any secret is expired (for gating CI).
- Classification: a secret expires on `lastRotated + rotationPolicyDays`;
  due today or overdue → `expired`; due within the warning window → `warning`.

## Layout

- `src/types.ts` — domain types (`Secret`, `SecretStatus`, `RotationReport`)
- `src/validator.ts` — classification and report building (pure, UTC day math)
- `src/format.ts` — markdown / JSON renderers and notification messages
- `src/config.ts` — config loading with distinct, actionable error messages
- `src/cli.ts` — argument parsing; `runCli` is pure and unit-tested
- `tests/` — Bun test suite built red/green TDD, one file per cycle,
  including workflow structure tests (`tests/workflow.test.ts`)
- `fixtures/secrets.json` — default mock configuration

## Testing

```sh
bun test                          # unit + workflow structure tests
bun run scripts/run-act-tests.ts  # full pipeline via act (writes act-result.txt)
```

The act harness stages each test case into a temp git repo (swapping in that
case's fixture and copying the host `bun`/`actionlint` binaries into `bin/`
so the container needs no network), runs `act push --rm --pull=false`, and
asserts exact expected report values plus "Job succeeded" for both jobs.

## CI

`.github/workflows/secret-rotation-validator.yml` runs on push, pull request,
a weekly schedule, and manual dispatch (with a configurable `warning_days`
input). The `test` job runs `bun test`; the dependent `report` job generates
both report formats and appends the markdown to the job summary.
`REPORT_DATE` is pinned because the data is mock; remove it to evaluate
against the current date.
