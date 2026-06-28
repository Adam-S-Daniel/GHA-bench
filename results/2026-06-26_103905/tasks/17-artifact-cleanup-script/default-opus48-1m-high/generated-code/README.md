# Artifact Cleanup Planner

Applies retention policies to a list of CI artifacts, decides which to delete,
and prints a deletion plan plus a summary (space reclaimed, retained vs
deleted). Supports a dry-run mode. Pure Python standard library; pytest is the
only test dependency.

## Retention policies

Policies are applied in a fixed, documented order so results are deterministic.
Once an artifact is marked for deletion it keeps its first (highest-precedence)
reason and is excluded from later rules' accounting:

1. **`max_age_days`** — delete artifacts strictly older than N days (relative to
   `now`).
2. **`keep_latest_n_per_workflow`** — for each `workflow_run_id`, keep the N
   newest surviving artifacts; delete the rest.
3. **`max_total_size`** — if surviving artifacts still exceed the byte cap,
   evict the oldest survivors until the total fits.

Any policy left unset (`null`) is disabled.

## Usage

```bash
python3 artifact_cleanup.py --input fixtures/case_combined.json            # LIVE
python3 artifact_cleanup.py --input fixtures/case_max_age.json --dry-run   # plan only
python3 artifact_cleanup.py --input fixtures/case_max_age.json --now 2027-01-01T00:00:00+00:00
```

The input is a JSON file: `{ "now": <iso8601?>, "policies": {...},
"artifacts": [{ "name", "size", "created_at", "workflow_run_id" }, ...] }`.
`now` is injectable (config field or `--now`) so runs are reproducible; bad
input fails with a clear message and a non-zero exit code.

## Tests (red/green TDD)

- `test_artifact_cleanup.py` — unit tests, built one failing test at a time:
  parsing → each policy → composition/precedence → config loading → error
  handling → rendering → CLI.
- `test_workflow.py` — structure tests for the GitHub Actions workflow
  (triggers, jobs, dependency, `actions/checkout@v4`, referenced files exist,
  actionlint passes).

```bash
python3 -m pytest test_artifact_cleanup.py test_workflow.py -v
```

## CI pipeline (GitHub Actions + act)

`.github/workflows/artifact-cleanup-script.yml` runs the unit suite, then a
matrix job that runs the planner against each fixture (one job per case, each
with its own verifiable plan).

`run_act_tests.py` is the end-to-end harness: it builds a temp git repo, runs
the workflow once via `act push --rm`, writes all output to `act-result.txt`,
and asserts act exited 0, every job reported "Job succeeded", and each fixture
case produced its EXACT known-good summary numbers.

```bash
python3 run_act_tests.py
```
