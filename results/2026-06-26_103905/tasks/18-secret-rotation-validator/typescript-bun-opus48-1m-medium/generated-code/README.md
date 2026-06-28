# Secret Rotation Validator

A small TypeScript/Bun tool that reads a configuration of secrets (name,
last-rotated date, rotation policy in days, and the services that require them),
identifies which secrets are **expired** or **expiring** within a configurable
warning window, and emits a grouped rotation report as either a **markdown
table** or **JSON**.

## Layout

| Path | Purpose |
| --- | --- |
| `src/validator.ts` | Domain model + pure `classifySecret` urgency logic. |
| `src/config.ts` | Parse + validate a JSON config, with descriptive errors. |
| `src/report.ts` | Build a grouped, summarised report from a config. |
| `src/format.ts` | Render a report as markdown or JSON. |
| `src/cli.ts` | CLI orchestration (`runCli`) + thin `main()` entry point. |
| `tests/` | Bun unit tests (written red/green TDD) + workflow structure tests. |
| `fixtures/` | Mock secret configs, including per-case fixtures under `fixtures/cases/`. |
| `harness/act-harness.ts` | Runs the GitHub Actions workflow through `act` per fixture. |
| `.github/workflows/secret-rotation-validator.yml` | The CI/CD pipeline. |

## Usage

```bash
# Markdown report (default). Exits 1 if any secret is expired.
bun run src/cli.ts --config fixtures/secrets.json

# JSON output, custom warning window, pinned reference date.
bun run src/cli.ts --config fixtures/secrets.json \
  --format json --warning-window 30 --now 2026-06-27
```

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | All secrets OK (none expired). |
| 1 | One or more secrets are expired. |
| 2 | Usage, configuration, or I/O error. |

## Classification rules

For each secret, with an injectable reference date `now`:

```
dueDate      = lastRotated + rotationPolicyDays
daysUntilDue = dueDate - now
expired   when daysUntilDue < 0
warning   when 0 <= daysUntilDue <= warningWindowDays
ok        otherwise
```

## Testing

```bash
# Fast unit + workflow-structure tests (red/green TDD).
bun test

# Full pipeline integration: runs the workflow through act for every fixture,
# writing all output to act-result.txt and asserting exact expected values.
bun run harness/act-harness.ts
```

The GitHub Actions workflow pins `REPORT_NOW=2026-06-27` so the report is
deterministic regardless of when `act` runs.
