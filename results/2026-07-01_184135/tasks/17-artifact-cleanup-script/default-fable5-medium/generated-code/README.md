# Artifact Cleanup Planner

Applies retention policies to a list of CI artifacts (mock data) and
produces a deletion plan with a summary. Built with red/green TDD in Python.

## Retention policies (applied in order)

1. **max age** (`--max-age-days N`) — artifacts older than N days are deleted.
2. **keep-latest-N** (`--keep-latest N`) — within each workflow run, only the
   N newest artifacts are kept.
3. **total size budget** (`--max-total-size BYTES`) — if the surviving set
   still exceeds the budget, the oldest survivors are evicted until it fits.

Every deletion records the policy that caused it. `--dry-run` prints the plan
without performing (mock) deletions; `--now ISO8601` pins the reference time
for deterministic results; `--output plan.json` writes the full plan as JSON.

```sh
python3 artifact_cleanup.py --input fixtures/artifacts.json \
  --now 2026-07-01T00:00:00Z \
  --max-age-days 30 --keep-latest 2 --max-total-size 2000 --dry-run
```

The output ends with a machine-parseable summary block
(`RETAINED_COUNT=`, `DELETED_COUNT=`, `SPACE_RECLAIMED_BYTES=`,
`RETAINED_BYTES=`, `DRY_RUN=`) that the CI pipeline tests assert on.

## Layout

- `artifact_cleanup.py` — planner core (pure `build_plan`) + CLI layer.
- `tests/test_artifact_cleanup.py` — unit tests for policies, summary, parsing.
- `tests/test_cli.py` — CLI tests: dry-run vs execute, error handling.
- `tests/test_workflow_structure.py` — workflow YAML structure + actionlint.
- `.github/workflows/artifact-cleanup-script.yml` — CI pipeline: unit-test job,
  then a cleanup-plan job that applies the policy from `cleanup-config.env`
  to `fixtures/artifacts.json`.
- `run_pipeline_tests.py` — end-to-end harness: runs every test case through
  the workflow via `act push` in a throwaway git repo per case, appends output
  to `act-result.txt`, and asserts exact expected values and job success.

## Running

```sh
python3 -m pytest tests/ -v        # unit + structure tests
python3 run_pipeline_tests.py      # full pipeline via act (needs Docker)
```
