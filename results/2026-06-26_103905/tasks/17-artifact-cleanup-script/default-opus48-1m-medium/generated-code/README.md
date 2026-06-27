# Artifact Cleanup

Applies retention policies to a set of (mock) build artifacts, decides which to
delete, and produces a deletion plan + summary. Supports dry-run mode.

Built with **PowerShell + Pester** using strict red/green TDD.

## Retention policies

Policies are applied in a deterministic order (so results are predictable):

1. **`maxAgeDays`** — delete artifacts older than _N_ days (relative to a
   reference "now", which is injectable for testability).
2. **`keepLatestN`** — per workflow, keep only the _N_ newest artifacts.
3. **`maxTotalSizeBytes`** — if the survivors still exceed the size cap, delete
   the oldest survivors first until the total is within the cap.

An artifact removed by an earlier policy is not re-evaluated by later ones. Each
deleted artifact carries a human-readable `Reason`.

## Files

| File | Purpose |
|------|---------|
| `ArtifactCleanup.psm1` | Core library: `New-Artifact`, `Get-ArtifactDeletionPlan`, `Get-ArtifactSummary`, `ConvertTo-Artifact`, `Invoke-ArtifactCleanup`. |
| `ArtifactCleanup.Tests.ps1` | Pester unit tests (the TDD red/green suite). Runs inside CI. |
| `Invoke-Cleanup.ps1` | CLI entry point: reads a scenario JSON, prints a machine-parseable plan. |
| `fixtures/*.json` | Mock scenarios (policy + reference time + artifacts). |
| `.github/workflows/artifact-cleanup-script.yml` | CI pipeline (test job → cleanup job). |
| `Workflow.Tests.ps1` | Structure tests for the workflow (triggers, jobs, deps, actionlint). |
| `run-act-tests.ps1` | E2E harness: runs every fixture case through `act`, asserts exact output, writes `act-result.txt`. |

## Scenario JSON shape

```json
{
  "now": "2026-06-27T00:00:00Z",
  "dryRun": true,
  "policy": { "maxAgeDays": 7, "keepLatestN": 2, "maxTotalSizeBytes": 1000 },
  "artifacts": [
    { "name": "build.zip", "sizeBytes": 500, "createdAt": "2026-06-01T00:00:00Z",
      "workflowName": "ci", "workflowRunId": 101 }
  ]
}
```

## Running

```bash
# Unit tests
pwsh -c "Invoke-Pester -Path ./ArtifactCleanup.Tests.ps1"

# Workflow structure tests
pwsh -c "Invoke-Pester -Path ./Workflow.Tests.ps1"

# CLI directly
pwsh -File ./Invoke-Cleanup.ps1 -ScenarioPath fixtures/combined.json

# Full end-to-end through GitHub Actions (act) -> writes act-result.txt
pwsh -File ./run-act-tests.ps1
```

## CI pipeline

The workflow has two jobs with a dependency:

- **test** — runs the Pester unit suite.
- **cleanup** (`needs: test`) — runs the CLI against `fixtures/scenario.json`
  (the harness overwrites this path with each test case's fixture).

Triggers: `push`, `pull_request`, `workflow_dispatch`, and a daily `schedule`.
Permissions are least-privilege (`contents: read`).
