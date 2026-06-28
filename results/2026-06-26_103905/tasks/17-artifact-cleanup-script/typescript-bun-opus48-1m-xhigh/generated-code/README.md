# Artifact Cleanup Script

Applies retention policies to a list of CI artifacts, decides which to delete,
and produces a deletion plan + summary. Written in **TypeScript** for the
**Bun** runtime and developed with red/green TDD.

## What it does

Given artifacts (`name`, `sizeBytes`, `createdAt`, `workflowRunId`, optional
`workflowName`), it applies up to three retention policies and reports the plan:

| Policy | Meaning |
| --- | --- |
| `maxAgeDays` | Delete artifacts older than N days. |
| `keepLatestNPerWorkflow` | Per workflow, keep only the N most-recent artifacts. |
| `maxTotalSizeBytes` | Cap total retained size; evict oldest survivors until it fits. |

### How the policies combine (deterministic order)

1. **max-age** — flag everything older than `now - maxAgeDays`.
2. **keep-latest-n** — within each workflow group (keyed by `workflowName`,
   falling back to `workflowRunId`), flag everything past the N newest.
3. **max-total-size** — of the artifacts that survived rules 1 & 2, if their
   combined size still exceeds the cap, evict **oldest-first** until it fits.

Each deleted artifact records *why* it was deleted (`reasons`). `now` is
injectable, so age calculations are fully reproducible. **Dry-run** mode marks
the plan as informational without changing any decisions.

## Files

| File | Purpose |
| --- | --- |
| `cleanup.ts` | Library (`planCleanup`) + CLI. |
| `cleanup.test.ts` | Unit tests for the planning logic (TDD). |
| `fixtures/*.json` | Self-contained scenarios (`now` + `dryRun` + `policy` + `artifacts`). |
| `.github/workflows/artifact-cleanup-script.yml` | CI/CD pipeline (test → cleanup-plan). |
| `workflow-structure.test.ts` | Asserts workflow structure + runs actionlint. |
| `act-harness.test.ts` | Runs every test case through the workflow via `act`; writes `act-result.txt`. |

## Usage

```bash
# Run from a self-contained scenario file
bun run cleanup.ts --config fixtures/case-combined.json

# Or provide artifacts + policy flags separately
bun run cleanup.ts --artifacts artifacts.json \
  --max-age-days 30 --keep-latest 3 --max-total-size 1000000 --dry-run

# JSON output / persist the plan
bun run cleanup.ts --config fixtures/scenario.json --format json --output plan.json
```

If `GITHUB_STEP_SUMMARY` is set (as in Actions), a Markdown summary is appended
to the job summary.

## Tests

```bash
bun test                       # full suite (unit + workflow structure + act e2e)
bun test cleanup.test.ts       # fast unit tests only
```

The act harness drives the **real** workflow in Docker for three scenarios and
asserts the pipeline emits the exact known-good numbers, saving all output to
`act-result.txt`.
