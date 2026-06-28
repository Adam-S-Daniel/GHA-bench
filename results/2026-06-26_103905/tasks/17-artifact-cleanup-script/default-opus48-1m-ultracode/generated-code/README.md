# Artifact Cleanup Script

Applies retention policies to a list of GitHub Actions artifacts (mock data with
`name`, `size`, `created_at`, `workflow_run_id`), decides which to delete, and
prints a deletion plan with a summary. Supports a dry-run mode.

Implemented in **Python 3** (standard library only) using **red/green TDD**.

## Files

| File | Purpose |
|------|---------|
| `artifact_cleanup.py` | The tool: parsing, the policy engine, rendering, and a CLI. |
| `fixtures/*.json` | Self-contained test inputs (artifacts + policies + a fixed `now`). |
| `tests/test_artifact_cleanup.py` | Unit tests (the TDD red/green cycles). |
| `tests/test_workflow_structure.py` | Static checks of the workflow YAML + actionlint. |
| `tests/test_workflow_act.py` | End-to-end run of the workflow in Docker via `act`. |
| `.github/workflows/artifact-cleanup-script.yml` | CI/CD pipeline that runs the script. |
| `act-result.txt` | Captured `act` output + per-case parsed results (generated). |

## Retention policies

Policies combine as a **union of deletion conditions** — an artifact is deleted if
any rule flags it, and reasons accumulate. Applied in order:

1. **`max_age_days`** — delete artifacts strictly older than the cutoff (an
   artifact exactly N days old is kept).
2. **`keep_latest_n`** — within each `workflow_run_id`, keep only the N newest
   artifacts (by creation date); flag the rest.
3. **`max_total_size`** — among the artifacts still retained after (1) and (2),
   evict the **oldest** survivors until their combined size fits the budget.

The summary reports total space reclaimed and retained-vs-deleted counts/sizes.

## Usage

```bash
python3 artifact_cleanup.py --input fixtures/combined.json            # text report
python3 artifact_cleanup.py --input fixtures/combined.json -f json    # JSON
python3 artifact_cleanup.py --input fixtures/combined.json --no-dry-run
```

The config JSON looks like:

```json
{
  "now": "2026-06-28T00:00:00Z",
  "dry_run": true,
  "policies": {"max_age_days": 30, "keep_latest_n": 2, "max_total_size": 1500},
  "artifacts": [
    {"name": "build", "size": 500, "created_at": "2026-06-20T00:00:00Z", "workflow_run_id": "ci-1"}
  ]
}
```

The text output ends with greppable `KEY=value` lines
(`DELETED_COUNT=`, `RETAINED_COUNT=`, `SPACE_RECLAIMED=`, `DRY_RUN=`) for CI assertions.

## Tests

```bash
python3 -m pytest -q                 # fast unit + workflow-structure tests
RUN_ACT=1 python3 -m pytest -q       # also runs the Docker/act end-to-end test
```

The workflow uses a **matrix** (one job per fixture case) so a single `act push`
exercises every case while keeping per-case isolation. The act test writes the
full log and a per-case PASS/FAIL breakdown to `act-result.txt`.
