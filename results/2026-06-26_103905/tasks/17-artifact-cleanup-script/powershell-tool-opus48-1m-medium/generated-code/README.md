# Artifact Cleanup Planner (PowerShell)

Applies retention policies to a set of CI artifacts and produces a deletion
plan with a summary (space reclaimed, retained vs deleted). Supports dry-run.

## Files

| File | Purpose |
|------|---------|
| `ArtifactCleanup.psm1` | Core, side-effect-free planning logic (`Get-ArtifactCleanupPlan`). |
| `Invoke-ArtifactCleanup.ps1` | CLI front end: reads a JSON fixture, runs the planner, prints a report + machine-parseable lines. |
| `ArtifactCleanup.Tests.ps1` | Pester unit tests for the planning module (TDD red/green). |
| `Workflow.Tests.ps1` | Structure tests + end-to-end tests that run the workflow through `act`. |
| `fixtures/*.json` | Mock artifact data / test cases. `case.json` is the default the workflow reads. |
| `.github/workflows/artifact-cleanup-script.yml` | CI pipeline that runs the unit tests then the planner. |

## Retention policies

All optional; `0` (or omitted) disables a policy. They are applied in order:

1. **Max age** (`maxAgeDays`) — delete artifacts strictly older than N days.
2. **Keep latest N** (`keepLatestN`) — per `workflowRunId`, keep only the N
   newest artifacts; delete the rest.
3. **Max total size** (`maxTotalSizeBytes`) — if survivors still exceed the
   cap, drop oldest-first until the retained total fits.

An artifact deleted by more than one policy keeps the *first* matching reason.

## Run the tests

```bash
# Unit tests (fast, no Docker)
pwsh -c 'Invoke-Pester -Path ./ArtifactCleanup.Tests.ps1'

# Full workflow tests through act (requires Docker + the act-ubuntu-pwsh image)
pwsh -c 'Invoke-Pester -Path ./Workflow.Tests.ps1'
```

`Workflow.Tests.ps1` builds an isolated temp git repo per fixture case, runs
`act push --rm`, appends all output to `act-result.txt`, and asserts the exact
`PLAN_SUMMARY` values for each case.

## Run the planner directly

```bash
pwsh ./Invoke-ArtifactCleanup.ps1 -InputPath ./fixtures/case-combined.json
```
