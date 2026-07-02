# Artifact Cleanup Script (PowerShell)

Applies retention policies to CI artifact metadata (mock data) and produces a
deletion plan with a summary. Built test-first with Pester (red/green TDD).

## Layout

| Path | Purpose |
| --- | --- |
| `src/ArtifactCleanup.psm1` | Policy engine: `Get-ArtifactCleanupPlan` (pure planner) and `Invoke-ArtifactCleanup` (executor with injectable deleter + dry-run) |
| `Invoke-ArtifactCleanup.ps1` | CLI entry point: JSON in, plan + `RESULT` summary lines out |
| `ci/run-cleanup.ps1` | CI wrapper that reads `ci/params.json` |
| `tests/` | Pester suites (engine, CLI, workflow structure) + JSON fixtures |
| `.github/workflows/artifact-cleanup-script.yml` | CI workflow: Pester job, then cleanup-plan job |
| `run-act-tests.ps1` | End-to-end harness: runs every test case through the workflow via `act`, writes `act-result.txt` |

## Policy semantics

1. **Keep-latest-N per workflow** (`-KeepLatestPerWorkflow`): the newest N
   artifacts of each workflow run are *protected* — no rule may delete them.
2. **Max age** (`-MaxAgeDays`): unprotected artifacts older than the cutoff
   are deleted (reason `MaxAge`).
3. **Max total size** (`-MaxTotalSizeBytes`): oldest unprotected survivors are
   evicted (reason `MaxTotalSize`) until the retained total fits the budget.
   Protected artifacts are kept even if the budget is still exceeded.

Every policy is optional; omitted policies simply don't apply.

## Usage

```powershell
./Invoke-ArtifactCleanup.ps1 -ArtifactsPath tests/fixtures/sample-artifacts.json `
    -MaxAgeDays 30 -KeepLatestPerWorkflow 1 -MaxTotalSizeBytes 157286400 `
    -ReferenceDate 2026-07-01T00:00:00Z -DryRun -PlanPath plan.json
```

`-DryRun` reports the plan without invoking the deleter. `-ReferenceDate`
fixes "now" for deterministic runs; it defaults to the current UTC time.

## Tests

```powershell
Invoke-Pester -Path tests   # unit + CLI + workflow-structure tests
./run-act-tests.ps1         # full pipeline runs via act (writes act-result.txt)
```
