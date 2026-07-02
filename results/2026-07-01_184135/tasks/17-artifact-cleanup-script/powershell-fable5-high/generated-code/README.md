# Artifact Cleanup Script (PowerShell)

Applies retention policies to a mock inventory of CI artifacts (name, size,
creation date, workflow run ID), produces a deletion plan with a summary
(space reclaimed, retained vs deleted), and supports dry-run mode.

## Files

| File | Purpose |
|------|---------|
| `ArtifactCleanup.psm1` | Policy engine: `Get-ArtifactRetentionPlan`, `Invoke-ArtifactCleanup`, `Assert-ValidArtifact` |
| `Invoke-ArtifactCleanup.ps1` | CLI: reads a JSON config (artifacts + policy + reference date), prints plan + summary |
| `fixtures/*.json` | Mock artifact inventories with policies and hand-computed expected outcomes |
| `tests/ArtifactCleanup.Tests.ps1` | Pester unit + CLI tests (17), built red/green TDD cycle by cycle |
| `tests/Workflow.Tests.ps1` | Workflow structure tests (13): YAML parse, triggers/jobs/steps, file references, actionlint exit 0 |
| `tests/Run-ActTests.ps1` | End-to-end harness: runs each test case through the workflow via `act`, writes `act-result.txt` |
| `.github/workflows/artifact-cleanup-script.yml` | CI pipeline: `test` (Pester) → `cleanup-plan` (runs the script on the fixture) |

## Policy semantics

Applied in this order by `Get-ArtifactRetentionPlan`:

1. **Keep-latest-N per workflow** — the N newest artifacts of each workflow
   run are *protected* and never deleted by any policy.
2. **Max age** — unprotected artifacts older than `maxAgeDays` (relative to
   the config's fixed `referenceDate`, keeping runs deterministic) are deleted.
3. **Max total size** — if the retained set still exceeds `maxTotalSizeMB`,
   the oldest unprotected artifacts are evicted until it fits (best-effort
   when protected artifacts alone exceed the cap).

Dry-run mode (`policy.dryRun: true`) prints the full plan and summary but
never invokes the deleter. The deleter is an injectable scriptblock, mocked
in tests.

## Running

```powershell
Invoke-Pester                                              # 30 tests, all green
./Invoke-ArtifactCleanup.ps1 -ConfigPath fixtures/case1.json
pwsh -NoProfile -File tests/Run-ActTests.ps1               # full E2E via act (Docker)
```

The act harness builds a temp git repo per test case (project files + that
case's fixture copied over `fixtures/artifacts.json`), runs `act push --rm`,
appends the delimited output to `act-result.txt`, and asserts exit code 0,
`Job succeeded` for both jobs, and the exact expected plan/summary values.
