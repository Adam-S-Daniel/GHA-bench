# Secret Rotation Validator

A TypeScript/Bun tool that reads a configuration of secrets (name, last-rotated
date, rotation policy in days, required-by services), classifies each secret by
rotation urgency (`expired`, `warning`, `ok`) relative to a configurable warning
window, and produces a rotation report as a **markdown table** or **JSON**.

## Usage

```bash
bun run src/cli.ts --input fixtures/secrets.json --warning 14 --format markdown
bun run src/cli.ts --input fixtures/secrets.json --format json --now 2026-06-27
```

Options:

| Flag | Description | Default |
| --- | --- | --- |
| `-i, --input <file>` | Path to the secrets JSON config (required) | — |
| `-w, --warning <days>` | Warning window in days | `14` |
| `-f, --format <fmt>` | `markdown` or `json` | `markdown` |
| `--now <date>` | Override the reference "now" (ISO date); useful for deterministic CI | today |
| `--fail-on-expired` | Exit non-zero if any secret is expired | off |

Exit codes: `0` success, `1` expired secrets found under `--fail-on-expired`,
`2` usage / parse / I/O error.

### Config format

Either a bare array, or an object with a `secrets` key:

```json
{
  "secrets": [
    { "name": "db-password", "lastRotated": "2026-06-01", "rotationPolicyDays": 90, "requiredBy": ["api"] }
  ]
}
```

## Classification rules

For each secret, given a reference date `now`:

- `daysSinceRotation = floor((now - lastRotated) / 1 day)`
- `daysUntilExpiry = rotationPolicyDays - daysSinceRotation`
- `expired` when `daysUntilExpiry <= 0` (due today or overdue)
- `warning` when `0 < daysUntilExpiry <= warningWindowDays`
- `ok` otherwise

## Project layout

- `src/types.ts` — shared interfaces and types
- `src/validator.ts` — pure classification / report-building logic
- `src/report.ts` — markdown / JSON renderers
- `src/config.ts` — input parsing + validation
- `src/cli.ts` — CLI argument parsing and orchestration
- `scripts/summarize.ts` — emits a machine-readable summary line for CI
- `tests/*.test.ts` — TDD unit suites + workflow-structure tests + act integration
- `.github/workflows/secret-rotation-validator.yml` — CI/CD pipeline

## Testing

Built with red/green TDD. Run everything with:

```bash
bun test
```

This runs the unit suites, the workflow-structure tests (parse YAML, verify
script paths, run `actionlint`), and the **act integration suite**
(`tests/act.test.ts`), which executes the real GitHub Actions workflow through
[`act`](https://github.com/nektos/act) for several fixtures and asserts the
exact `ROTATION_SUMMARY` counts. All act output is appended to `act-result.txt`.

> The act suite requires Docker + `act`. It is automatically skipped when running
> *inside* act (`ACT` env var) so the workflow's own test step never recurses.

## GitHub Actions workflow

`.github/workflows/secret-rotation-validator.yml` runs on push, pull_request, a
daily schedule, and manual dispatch. It checks out the repo, installs Bun,
runs the unit tests, then generates the rotation report (JSON + markdown),
emits a machine-readable summary, and writes the report to the job summary.
The `NOW` value is pinned for deterministic output.
