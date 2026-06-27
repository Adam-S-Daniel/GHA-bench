# Secret Rotation Validator

Identifies secrets that are **expired** or **expiring** within a configurable
warning window, generates a rotation report, and emits notifications grouped by
urgency (`expired` / `warning` / `ok`). Supports **markdown** and **JSON** output.

Written in TypeScript, run with [Bun](https://bun.sh).

## Usage

```bash
bun run validate.ts --config fixtures/secrets.json --format markdown
bun run validate.ts --config fixtures/secrets.json --format json --now 2026-06-27
```

### Options

| Flag | Default | Description |
| --- | --- | --- |
| `--config <path>` | `secrets.json` | Path to the secrets config JSON |
| `--format <markdown\|json>` | `markdown` | Output format |
| `--warning-window <days>` | from config (or 14) | Override the warning window |
| `--now <YYYY-MM-DD>` | today (UTC) | Reference date (deterministic testing/CI) |
| `--output <path>` | — | Also write the report to a file |
| `--fail-on <none\|warning\|expired>` | `none` | Exit non-zero at/above this urgency |
| `-h, --help` | — | Show help |

Exit codes: `0` success, `1` policy violation (`--fail-on`), `2` operational error.

## Config format

```json
{
  "warningWindowDays": 14,
  "secrets": [
    {
      "name": "DATABASE_PASSWORD",
      "lastRotated": "2026-01-01",
      "rotationPolicyDays": 90,
      "requiredBy": ["api", "worker"]
    }
  ]
}
```

A secret is **expired** when `lastRotated + rotationPolicyDays` is before `now`,
**warning** when it expires within `warningWindowDays` (inclusive, incl. today),
otherwise **ok**.

## Project layout

- `src/validator.ts` — pure domain logic (parse, classify, group, report)
- `src/report.ts` — markdown + JSON formatters
- `src/cli.ts` — argument parsing + run orchestration (pure, testable)
- `validate.ts` — executable entry point (owns all I/O)
- `tests/` — Bun tests (`bun test`): unit tests + workflow/act integration
- `.github/workflows/secret-rotation-validator.yml` — CI pipeline

## Testing

```bash
bun test                       # all tests (unit + structural + act e2e)
bun test tests/validator.test.ts  # fast unit tests only
```

Built red/green with TDD. The workflow tests run the actual GitHub Actions
pipeline through [`act`](https://github.com/nektos/act) for two fixtures and
assert on exact output; the full run log is written to `act-result.txt`.
