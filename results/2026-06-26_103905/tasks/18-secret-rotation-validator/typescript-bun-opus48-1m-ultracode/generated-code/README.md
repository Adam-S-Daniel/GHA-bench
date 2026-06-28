# Secret Rotation Validator

A small TypeScript/Bun tool that reads a configuration of secrets (name,
last-rotated date, rotation policy, and the services that depend on them),
identifies which secrets are **expired** or **expiring soon**, and emits a
rotation report grouped by urgency. It ships with a GitHub Actions workflow that
runs the check on every push/PR and on a daily schedule.

## How urgency is decided

For each secret:

```
expiryDate      = lastRotated + rotationPolicyDays
daysUntilExpiry = expiryDate - now            (negative ⇒ overdue)
```

| Condition                                   | Urgency   |
| ------------------------------------------- | --------- |
| `daysUntilExpiry < 0`                       | `expired` |
| `0 ≤ daysUntilExpiry ≤ warningWindowDays`   | `warning` |
| `daysUntilExpiry > warningWindowDays`        | `ok`      |

All date math is done in **UTC** so results never depend on the machine's
timezone — the same fixtures produce identical reports locally and in CI.

## Usage

```bash
bun run validate.ts --config fixtures/secrets.json \
  --warning-days 14 \
  --format markdown \
  --now 2026-06-28 \
  --fail-on expired
```

| Flag             | Default    | Description                                                        |
| ---------------- | ---------- | ------------------------------------------------------------------ |
| `--config`       | _(required)_ | Path to the secrets JSON config.                                 |
| `--warning-days` | `14`       | Secrets expiring within this many days are flagged `warning`.       |
| `--format`       | `markdown` | Output format: `markdown` \| `json` \| `github`.                   |
| `--now`          | today (UTC) | Reference date for the evaluation (`YYYY-MM-DD`). Enables deterministic CI. |
| `--fail-on`      | `none`     | Exit `1` when this urgency is present: `none` \| `warning` \| `expired`. |

**Exit codes:** `0` success · `1` `--fail-on` threshold breached · `2` usage/IO/validation error.

### Config format

```json
{
  "secrets": [
    {
      "name": "AWS_ACCESS_KEY",
      "lastRotated": "2026-01-01",
      "rotationPolicyDays": 90,
      "requiredBy": ["api", "worker"]
    }
  ]
}
```

A bare top-level array is also accepted. `requiredBy` is optional (defaults to `[]`).

### Output formats

- **`markdown`** — urgency-grouped tables, ideal for a GitHub Actions job summary.
- **`json`** — the full report object (summary + grouped secrets), machine-readable.
- **`github`** — `key=value` counter lines (`total`, `expired`, `warning`, `ok`)
  for appending to `$GITHUB_OUTPUT`.

## Project layout

```
validate.ts                 # CLI entrypoint (bun run validate.ts ...)
src/
  types.ts                  # domain interfaces
  validator.ts              # pure date math + evaluation + report building
  config.ts                 # parsing & strict validation of the config
  formatters.ts             # json / markdown / github renderers
  cli.ts                    # arg parsing + main() orchestration (injected I/O)
fixtures/
  secrets.json              # sample mixed-urgency config (workflow default)
  secrets-all-ok.json       # sample all-healthy config
tests/                      # bun test suites (see below)
.github/workflows/secret-rotation-validator.yml
```

## Tests (TDD)

Built red/green with `bun test`. The suite has two layers:

1. **Unit tests** (`validator`, `config`, `formatters`, `cli`) — fast, pure-logic
   coverage of every branch, written test-first.
2. **Acceptance tests** (`workflow-structure`, `act`) — parse and lint the
   workflow, then run **every behavioral case end-to-end through the GitHub
   Actions workflow via `act`** (Docker), asserting on exact expected values.
   Each `act` run is appended to `act-result.txt`.

```bash
bun test                 # everything (the act layer needs Docker)
bun test tests/cli.test.ts   # a single fast suite
```

## CI workflow

`.github/workflows/secret-rotation-validator.yml` runs on `push`,
`pull_request`, a daily `schedule`, and `workflow_dispatch` (with a tunable
warning window). It has two jobs:

- **`validate`** — checks out, installs Bun, runs the validator, publishes a
  markdown job summary, and exposes the summary counters as job outputs.
- **`report`** (`needs: validate`) — consumes those outputs, prints a verdict
  line, and raises non-fatal `::warning::`/`::notice::` annotations.

It passes `actionlint` cleanly and runs successfully under `act`.
