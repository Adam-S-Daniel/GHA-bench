# Artifact Cleanup Script

A TypeScript/Bun tool that applies retention policies to a set of CI artifacts
and produces a deletion plan with a summary (space reclaimed, retained vs.
deleted). Built with red/green TDD.

## What it does

Given a list of artifacts (`name`, `sizeBytes`, `createdAt`, `workflowRunId`)
and a retention policy, it decides which artifacts to delete and which to keep,
then prints a human-readable plan. Supports **dry-run** mode (plan only) and
**live** mode (reports the deletion as performed).

### Retention rules

The policy supports three optional, composable rules:

| Rule | Field | Meaning |
|------|-------|---------|
| Max age | `maxAgeDays` | Delete artifacts strictly older than N days. |
| Keep latest N | `keepLatestNPerWorkflow` | Keep only the N newest artifacts per `workflowRunId`. |
| Max total size | `maxTotalSizeBytes` | Evict oldest artifacts until the retained total fits the budget. |

**Combination semantics (documented & tested):** age and keep-latest-N each
mark artifacts for deletion independently; the deletion set is their **union**.
The size cap is applied **last**, only to the survivors, evicting oldest-first
until the retained total is within budget. This makes the outcome deterministic
regardless of which rules are present.

## Layout

```
src/
  cleanup.ts   Pure planner: planCleanup(artifacts, policy, {now}) -> DeletionPlan
  parse.ts     Validates untrusted JSON input -> typed CleanupInput (clear errors)
  render.ts    Renders a DeletionPlan to a stable, parseable text report
  cli.ts       Thin I/O layer: resolves args/env, reads fixture, prints, exit codes
tests/
  cleanup.test.ts   Planner unit tests (each retention rule + combinations + edges)
  parse.test.ts     Input validation tests
  render.test.ts    Report formatting tests
  cli.test.ts       End-to-end CLI orchestration tests
  workflow.test.ts  GitHub Actions workflow structure + actionlint tests
fixtures/
  sample.json       Example input
  ci-input.json     Input the CI workflow reads (overwritten per act test case)
harness/
  act-harness.ts    Runs every test case through the workflow via `act`
.github/workflows/
  artifact-cleanup-script.yml   CI pipeline that runs the tool
```

## Usage

```bash
# Unit tests (TDD suite)
bun test

# Run the tool
bun run src/cli.ts --fixture fixtures/sample.json --dry-run   # plan only
bun run src/cli.ts --fixture fixtures/sample.json             # live
FIXTURE_FILE=fixtures/sample.json DRY_RUN=true bun run src/cli.ts

# Run every case through the GitHub Actions workflow with act
bun run harness/act-harness.ts   # writes act-result.txt
```

Exit codes: `0` success, `1` runtime/validation error, `2` usage error.

## CI pipeline

`.github/workflows/artifact-cleanup-script.yml` runs on push, pull_request, a
weekly schedule, and manual dispatch. It has two jobs:

1. **test** — installs Bun and runs `bun test`.
2. **plan** — `needs: test`; installs Bun, verifies the fixture, and runs the
   CLI to print the deletion plan (dry-run by default for safety).

The workflow is validated with `actionlint` and executed locally with
[`act`](https://github.com/nektos/act). The act harness runs three fixtures end
to end and asserts the exact plan output for each, saving everything to
`act-result.txt`.
