# Artifact Cleanup Script (PowerShell)

Applies retention policies to a list of CI artifacts, decides which to delete,
and produces a deletion plan + summary (space reclaimed, retained vs deleted).
Supports a safe **dry-run** mode. Built red/green TDD with Pester, integrated
into a GitHub Actions workflow, and verified end-to-end through `act`.

## Files

| File | Purpose |
|------|---------|
| `ArtifactCleanup.psm1` | Pure retention engine + I/O helpers (no side effects). |
| `Invoke-Cleanup.ps1` | CLI entry point the workflow runs: load config → plan → print report. |
| `fixtures/artifacts.json` | Self-contained sample config (policies + reference date + artifacts). |
| `tools/Run-UnitTests.ps1` | Runs the hermetic Pester unit suite (used by the CI `test` job). |
| `.github/workflows/artifact-cleanup-script.yml` | The CI/CD workflow. |
| `tests/ArtifactCleanup.Tests.ps1` | Unit tests (Tag `Unit`) — run locally and inside the container. |
| `tests/Workflow.Tests.ps1` | Workflow-structure + actionlint tests (Tag `Workflow`). |
| `tests/ActAcceptance.Tests.ps1` | End-to-end tests that drive every case through `act` (Tag `Acceptance`). |
| `tests/AcceptanceHelpers.ps1` | Shared helpers for the act harness. |
| `act-result.txt` | Captured `act` output for all acceptance cases (required artifact). |

## Retention policies

An artifact is **deleted if any policy objects to it** (the reasons union);
otherwise it is retained. Policies are optional — omit one to skip it — and are
composed in this order:

1. **`maxAgeDays`** — delete artifacts created strictly before `now - N days`
   (the boundary day is kept).
2. **`keepLatestN`** — group artifacts by `workflowRunId`; within each group keep
   the `N` newest (by creation date) and delete the rest.
3. **`maxTotalSizeBytes`** — of whatever survives (1) and (2), if the retained
   total exceeds the cap, evict **oldest-first** until it fits.

Each deleted artifact records *every* reason that applied (e.g. `MaxAge|KeepLatestN`).

## Config / fixture schema

A single JSON file fully determines a run (which is what the act harness varies
per test case):

```json
{
  "referenceDate": "2026-06-28T00:00:00Z",
  "dryRun": true,
  "policies": { "maxAgeDays": 30, "keepLatestN": 2, "maxTotalSizeBytes": 10000 },
  "artifacts": [
    { "name": "build-logs", "sizeBytes": 2048,
      "createdAt": "2026-06-20T10:00:00Z", "workflowRunId": "1001" }
  ]
}
```

- `dryRun` defaults to `true` (a cleanup tool should never delete unless asked).
- `referenceDate` makes age-based output deterministic; defaults to the real now.
- All timestamps are normalised to UTC, so results are timezone-independent.

## Running

```powershell
# Generate a deletion plan from the default fixture
pwsh ./Invoke-Cleanup.ps1 -FixturePath fixtures/artifacts.json

# Unit tests only (fast, hermetic)
Invoke-Pester -Path tests/ArtifactCleanup.Tests.ps1 -Tag Unit

# Everything (unit + workflow-structure + act acceptance — needs Docker/act)
Invoke-Pester -Path tests/
```

## Workflow design

`artifact-cleanup-script.yml` triggers on `push`, `pull_request`, a weekly
`schedule`, and `workflow_dispatch`. Two jobs:

- **`test`** — installs/ensures Pester and runs the unit suite via `shell: pwsh`.
- **`cleanup`** — `needs: test`; runs `Invoke-Cleanup.ps1` to emit the plan and a
  GitHub job summary. It widens permissions to `actions: write` (what a real
  artifact deletion needs); the top level is least-privilege `contents: read`.

All `run:` steps use `shell: pwsh` (no `pwsh -File`/bash escaping). The workflow
passes `actionlint` cleanly and runs successfully under `act` in the pre-baked
`act-ubuntu-pwsh` container.

## Testing approach (TDD)

The engine was grown one behaviour at a time — write a failing test, add the
minimum code, refactor — across seven cycles: empty plan → `MaxAge` →
`KeepLatestN` → `MaxTotalSize` → policy composition + input validation →
`Invoke-ArtifactCleanup` dry-run/execution → JSON import + report rendering.
Acceptance is proven *through the pipeline*: each fixture case runs in the real
workflow via `act`, and the printed summary is asserted against exact,
hand-computed values.
