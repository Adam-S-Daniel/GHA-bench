# Artifact Cleanup

A TypeScript/Bun tool that applies retention policies to CI artifacts and
produces a deletion plan with a summary. Built with red/green TDD.

## Retention policies

Policies are additive — an artifact is deleted if **any** policy marks it. They
are applied in stages, each operating on the survivors of the previous stage:

1. **`maxAgeDays`** — delete artifacts older than N days.
2. **`keepLatestNPerWorkflow`** — within each `workflowRunId`, keep only the N
   most recently created artifacts.
3. **`maxTotalSizeBytes`** — if the retained set still exceeds the budget,
   delete the oldest artifacts first until it fits.

## Usage

```bash
bun run src/cli.ts --input fixtures/artifacts.json \
  --max-age-days 90 \
  --keep-latest-n 2 \
  --max-total-size-bytes 15000000 \
  --now 2026-06-27T00:00:00Z \
  --dry-run
```

- `--dry-run` reports the plan without claiming any deletion was executed.
- `--now <iso>` overrides "now" for deterministic age calculations.

Output is human-readable and machine-assertable (`SUMMARY ...`, `RESULT ...`,
`DELETE ...`, `RETAIN ...` lines).

## Project layout

- `src/cleanup.ts` — pure policy/summary/validation logic.
- `src/cli.ts` — argument parsing and report rendering.
- `src/*.test.ts` — unit tests (logic, CLI, workflow structure).
- `.github/workflows/artifact-cleanup-script.yml` — CI workflow.
- `harness/run-act-tests.ts` — runs every case through the workflow via `act`.

## Testing

```bash
bun test                       # unit + workflow-structure tests
bun run harness/run-act-tests.ts   # end-to-end through act (writes act-result.txt)
```

Every artifact-cleanup behavior case is exercised through the GitHub Actions
workflow with `nektos/act`; results are appended to `act-result.txt`.
