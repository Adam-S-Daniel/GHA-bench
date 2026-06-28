# Artifact Retention Cleanup (PowerShell)

A small, test-driven PowerShell tool that applies retention policies to a list
of build artifacts, decides which to delete, and produces a deletion plan with a
summary. It supports a safe **dry-run** mode and runs inside a GitHub Actions
pipeline.

## What it does

Given artifact metadata (name, size, creation date, workflow run id), it applies
three retention policies and reports a plan:

| Policy | Parameter | Behaviour |
| --- | --- | --- |
| Max age | `MaxAgeDays` | Delete artifacts older than N days. The boundary is inclusive (exactly N days old is kept). |
| Keep latest N per workflow | `KeepLatestPerWorkflow` | Within each workflow run id, keep the N most-recent artifacts and delete the rest. |
| Max total size | `MaxTotalSizeBytes` | While the retained total exceeds the cap, delete the **oldest** retained artifact until it fits. |

### Composition model

The policies are **independent filters combined as a union of deletions**: an
artifact is retained only if it satisfies *every* enabled policy (it is within
the newest-N of its run **and** within the max age **and** it still fits under
the size cap). `MaxTotalSizeBytes` is the aggregate trim and therefore runs
last. This keeps all three policies genuinely composable — no single policy can
mask the others. Any policy left unset is simply skipped.

If `MaxTotalSizeBytes` is smaller than the largest individual artifact, a
warning is emitted (that artifact can never be retained under such a cap).

## Files

| File | Purpose |
| --- | --- |
| `ArtifactCleanup.psm1` | Core module: data loading, policy engine, reporting. |
| `Invoke-ArtifactCleanupCli.ps1` | CLI entry point used by the workflow. |
| `tests/ArtifactCleanup.Tests.ps1` | Pester suite (built test-first, red/green TDD). |
| `fixtures/*.json` | Self-contained scenario fixtures (policy + mode + mock artifacts). |
| `.github/workflows/artifact-cleanup-script.yml` | CI pipeline: runs the tests, then the plan. |
| `Run-ActTests.ps1` | End-to-end harness that runs every case through `act`. |

## Scenario file format

Each fixture bundles everything one run needs:

```json
{
  "referenceDate": "2026-06-28T00:00:00Z",
  "dryRun": true,
  "policy": { "maxAgeDays": 30, "keepLatestPerWorkflow": 2, "maxTotalSizeBytes": 2097152 },
  "artifacts": [
    { "Name": "build-output", "SizeBytes": 1048576, "CreatedAt": "2026-06-27T00:00:00Z", "WorkflowRunId": 1 }
  ]
}
```

`referenceDate` (defaults to now) makes age-based decisions deterministic, which
is what lets the tests assert exact values. `dryRun` defaults to `true` — a
destructive tool should be safe by default.

## Usage

```powershell
# Dry-run the bundled default scenario
./Invoke-ArtifactCleanupCli.ps1 -ScenarioPath fixtures/scenario.json

# Force execute (non-dry-run) mode
./Invoke-ArtifactCleanupCli.ps1 -ScenarioPath fixtures/scenario.json -Execute
```

The CLI prints a report whose summary uses stable `Key: value` lines
(`DeletedCount: 4`, `SpaceReclaimedBytes: 4194304`, …) so automation can parse
exact values.

## Testing

```powershell
# Unit + integration tests (fast)
Invoke-Pester -Path tests

# Full pipeline via act (slower: spins Docker containers)
./Run-ActTests.ps1            # all cases through act -> act-result.txt
./Run-ActTests.ps1 -StructureOnly   # static workflow checks only
```

The project was built using red/green/refactor TDD: every behaviour started as a
failing Pester test before the implementation existed.

## CI pipeline

`.github/workflows/artifact-cleanup-script.yml` runs on push, pull request, a
weekly schedule, and manual dispatch. It has two jobs:

1. **unit-tests** — runs the full Pester suite.
2. **cleanup-plan** (`needs: unit-tests`) — runs the CLI and publishes the plan
   to the job summary.

Steps use `shell: pwsh` and `actions/checkout@v4`, run in an isolated container,
and need no external services or secrets. The workflow passes `actionlint` and
executes successfully under `act`.
