# Artifact Cleanup (PowerShell)

Applies retention policies to a list of artifacts (mock metadata: name, size,
creation date, workflow name + run id), produces a **deletion plan**, and reports
a summary (space reclaimed, retained vs deleted). Supports **dry-run**.

## Retention policies (applied in this order)

1. **MaxAgeDays** — delete anything strictly older than the cutoff.
2. **KeepLatestPerWorkflow** — within each workflow group keep only the N newest.
3. **MaxTotalSizeBytes** — if survivors still exceed the budget, delete
   oldest-first until the retained total fits.

The engine (`Get-ArtifactRetentionPlan`) is pure — it never deletes anything.
`Invoke-ArtifactCleanup` optionally executes deletions via a `-DeleteAction`
callback and honours `-DryRun`.

## Layout

| Path | Purpose |
|------|---------|
| `src/ArtifactCleanup.psm1` | Module: import, plan, format, invoke. |
| `Invoke-Cleanup.ps1` | CLI entry point used by CI. |
| `fixtures/sample.json` | Default mock artifact data. |
| `tests/ArtifactCleanup.Tests.ps1` | Pester unit tests (red/green TDD). |
| `tests/Workflow.Tests.ps1` | Workflow structure + actionlint tests. |
| `tests/Invoke-ActTests.ps1` | Runs the workflow through `act`, asserts exact output. |
| `.github/workflows/artifact-cleanup-script.yml` | CI pipeline. |

## Running

```bash
# Unit + structure tests
pwsh -c "Invoke-Pester -Path tests/ArtifactCleanup.Tests.ps1,tests/Workflow.Tests.ps1"

# CLI
pwsh ./Invoke-Cleanup.ps1 -Path fixtures/sample.json -MaxAgeDays 30 \
  -KeepLatestPerWorkflow 2 -MaxTotalSizeBytes 2500 -DryRun

# Full end-to-end through GitHub Actions (act); writes act-result.txt
pwsh ./tests/Invoke-ActTests.ps1
```
