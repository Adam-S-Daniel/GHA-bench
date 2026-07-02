# Artifact Cleanup Script (TypeScript + Bun)

Applies retention policies to a (mock) CI artifact inventory, produces a
deletion plan with a summary, and optionally "executes" it. Built with
red/green TDD using Bun's built-in test runner.

## Usage

```sh
bun run src/cli.ts --artifacts fixtures/artifacts.json --config fixtures/policy.json [--dry-run]
```

- `--artifacts` — JSON array of artifacts: `{ id, name, sizeBytes, createdAt, workflowRunId }`
- `--config` — policy JSON: `{ maxAgeDays?, maxTotalSizeBytes?, keepLatestPerWorkflow?, referenceDate?, dryRun? }`
- `--dry-run` — forces dry-run regardless of the config (safety override)

The CLI prints a human-readable report, a `Summary:` line, and one
machine-readable line `::PLAN::{json}::ENDPLAN::` that CI tooling parses.

## Policy semantics (applied in order)

1. **max-age** — artifacts *strictly* older than `maxAgeDays` (relative to
   `referenceDate`, default: now) are deleted.
2. **keep-latest-N per workflow** — within each `workflowRunId`, only the N
   most recent artifacts survive (ties broken by higher id = newer).
3. **max-total-size** — if the survivors still exceed the byte cap, the oldest
   survivors are evicted until the total fits. Runs last so space freed by the
   other policies counts first.

An artifact doomed by several policies reports **all** of its reasons.
Dry-run mode plans everything but never invokes the deleter.

## Layout

- `src/types.ts` — domain types
- `src/planner.ts` — pure planning logic + validation
- `src/executor.ts` — carries out a plan through an injectable `ArtifactDeleter`
  (the CLI injects a logging mock since the data is mock)
- `src/parse.ts` — JSON parsing/validation with specific error messages
- `src/cli.ts` — command-line entry point
- `tests/` — unit + CLI + workflow-structure tests (`bun test`)
- `scripts/run-act-tests.ts` — end-to-end harness that runs every test case
  through the GitHub Actions workflow with `act` and asserts exact values
  (writes `act-result.txt`)

## CI

`.github/workflows/artifact-cleanup-script.yml` runs on push / PR / manual
dispatch / daily schedule: job `test` (bun test) then job `cleanup-plan`
(generates the deletion plan from `fixtures/`). Validated with `actionlint`
and executed locally via `act push`.

## Tests

```sh
bun test                          # unit + CLI + workflow-structure tests
bun run scripts/run-act-tests.ts  # full pipeline through act (slow)
```
