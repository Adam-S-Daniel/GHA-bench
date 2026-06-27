# Artifact Cleanup

A PowerShell tool that applies retention policies to CI build artifacts,
produces a deletion plan, and reports the space reclaimed. Supports dry-run
(the default). Built test-first with Pester and exercised end-to-end through a
GitHub Actions workflow run locally with `act`.

## Files

| File | Purpose |
|------|---------|
| `ArtifactCleanup.psm1` | Pure retention engine: `New-ArtifactCleanupPlan`, `Format-CleanupReport`. Computes a plan; never deletes. |
| `Invoke-Cleanup.ps1` | CLI wrapper. Reads a JSON fixture, builds a plan, prints a parseable report. Dry-run by default; `-Execute` flips it. |
| `ArtifactCleanup.Tests.ps1` | Pester unit tests for the engine (run inside CI via `act`). |
| `Workflow.Tests.ps1` | Pester structural tests for the workflow YAML + actionlint. |
| `Run-ActTests.ps1` | E2E harness: runs each fixture case through the workflow via `act`, captures `act-result.txt`, asserts exact values. |
| `.github/workflows/artifact-cleanup-script.yml` | The CI workflow (test job → cleanup-plan job). |
| `fixtures/*.json` | Mock artifact metadata + policy per test case. |

## Retention policies

A value of `0` disables that policy. Policies compose; an artifact is deleted if
*any* policy marks it.

1. **Max age** (`maxAgeDays`) — delete artifacts older than N days.
2. **Keep latest N per workflow** (`keepLatestPerWorkflow`) — within each
   `workflowRunId`, keep only the N newest; mark the rest.
3. **Max total size** (`maxTotalSize`, bytes) — after the above, if the retained
   total still exceeds the budget, drop the *oldest* survivors first until it fits.

## Fixture format

```json
{
  "now": "2026-06-26T00:00:00Z",          // optional: pins the clock for age math
  "policy": { "maxAgeDays": 30, "maxTotalSize": 1000, "keepLatestPerWorkflow": 2 },
  "artifacts": [
    { "name": "build-x", "size": 100, "creationDate": "2026-06-25T00:00:00Z", "workflowRunId": "run-1" }
  ]
}
```

## Running

```bash
# Unit + structure tests
pwsh -c "Invoke-Pester -Path ./ArtifactCleanup.Tests.ps1,./Workflow.Tests.ps1"

# The CLI directly (dry-run)
pwsh -File ./Invoke-Cleanup.ps1 -FixturePath ./fixtures/combined.json

# Full end-to-end through GitHub Actions via act (writes act-result.txt)
pwsh -File ./Run-ActTests.ps1
```

## Report format

`Format-CleanupReport` emits a stable, delimited block so CI can assert on exact
values:

```
PLAN_SUMMARY_BEGIN
TotalArtifacts: 4
Retained: 1
Deleted: 3
SpaceReclaimed: 1500
RetainedSize: 700
DryRun: True
PLAN_SUMMARY_END
DELETE: ancient [MaxAge,KeepLatest] size=100
...
RETAIN: r1-c size=700
```
