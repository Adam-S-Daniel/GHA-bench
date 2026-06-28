# Artifact Cleanup Script (PowerShell)

Applies retention policies to a set of build artifacts (mock metadata: name,
size, creation date, workflow run ID), decides what to delete, and produces a
deletion plan + summary. Supports **dry-run** mode. Built with red/green TDD
using Pester, and exercised end-to-end through a GitHub Actions workflow via
`act`.

## Files

| File | Purpose |
|------|---------|
| `ArtifactCleanup.psm1` | Core engine: `Get-ArtifactCleanupPlan` (pure planning) and `Invoke-ArtifactCleanup` (planning + dry-run/live execution). |
| `Invoke-ArtifactCleanup.ps1` | CLI entry point used by CI. Reads a JSON fixture, runs the engine, prints a human report + stable `ACLEANUP::key=value` markers. |
| `tests/ArtifactCleanup.Tests.ps1` | Pester **unit** tests for the engine (TDD). |
| `tests/Workflow.Tests.ps1` | Workflow **structure** tests + actionlint check + end-to-end `act` harness. |
| `fixtures/*.json` | Test-case input data (artifacts + policy + reference time). |
| `.github/workflows/artifact-cleanup-script.yml` | The CI/CD pipeline. |
| `act-result.txt` | Captured output of every `act` test case (generated). |

## Retention policy model (precedence)

Policies are applied in a fixed, deterministic order. Each is optional
(value `0`/absent disables it).

1. **keep-latest-N per workflow** — for each `workflowRunId`, the newest *N*
   artifacts are *protected* (a retention floor: never deleted by any policy).
   Everything beyond the newest *N* is deleted (`reason = KeepLatestN`).
2. **max-age** — non-protected artifacts older than `Now - maxAgeDays` are
   deleted (`reason = MaxAge`).
3. **max-total-size** — if the retained total still exceeds `maxTotalSizeBytes`,
   non-protected artifacts are evicted oldest-first (`reason = MaxTotalSize`)
   until within budget. Protected artifacts are never evicted, so the result may
   stay over budget — reported via the summary `OverBudget` flag.

Sorting is fully deterministic (`CreatedAt`, then `Name`) so identical inputs
always yield identical plans. A fixed `now` can be injected for reproducible
age calculations.

## Running

```pwsh
# Unit tests
Invoke-Pester ./tests/ArtifactCleanup.Tests.ps1

# Run the CLI against a fixture
./Invoke-ArtifactCleanup.ps1 -FixturePath fixtures/case-1-maxage.json

# Full workflow tests incl. act end-to-end (runs `act push` per case)
Invoke-Pester ./tests/Workflow.Tests.ps1
#   set $env:SKIP_ACT='1' to skip the slow act section
```

## Fixture format

```json
{
  "now": "2026-06-28T00:00:00Z",
  "dryRun": true,
  "policy": { "maxAgeDays": 30, "keepLatestN": 0, "maxTotalSizeBytes": 0 },
  "artifacts": [
    { "name": "build-1", "sizeBytes": 1000,
      "createdAt": "2026-01-01T00:00:00Z", "workflowRunId": "100" }
  ]
}
```
