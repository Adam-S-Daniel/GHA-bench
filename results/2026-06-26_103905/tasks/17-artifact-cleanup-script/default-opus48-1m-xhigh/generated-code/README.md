# Artifact Cleanup Script (Task 17)

A small, dependency-free Python tool that applies retention policies to a list of
build artifacts and produces a **deletion plan** with a summary. Supports
**dry-run** mode. Built test-first (red/green TDD) and exercised end-to-end
through a GitHub Actions workflow with `act`.

## Files

| Path | Purpose |
|------|---------|
| `artifact_cleanup.py` | The engine + CLI (pure stdlib). |
| `tests/test_artifact_cleanup.py` | Red/green TDD unit tests for the engine. |
| `tests/test_workflow_structure.py` | YAML structure + `actionlint` checks. |
| `tests/test_workflow_act.py` | Runs the workflow in Docker via `act` for 3 cases. |
| `fixtures/artifacts.json`, `fixtures/policy.json` | Default mock data the workflow reads. |
| `fixtures/cases/*/` | Per-case fixture data for the act harness. |
| `.github/workflows/artifact-cleanup-script.yml` | The CI/CD pipeline. |
| `act-result.txt` | Captured output of every `act` run (required artifact). |

## Data model

Each artifact is a JSON object. `workflow` is optional (defaults to `"default"`);
the core metadata named by the task is name / size / creation date / run id.

```json
{ "name": "build-archive", "size_bytes": 1048576,
  "created_at": "2026-06-01T10:00:00Z", "run_id": 12345, "workflow": "ci" }
```

A policy enables one or more rules:

```json
{ "max_age_days": 30, "keep_latest_n": 3, "max_total_size_bytes": 5000000 }
```

## Retention policies

1. **`max_age_days`** – delete artifacts older than the cutoff (`now - N days`).
2. **`keep_latest_n`** – within each `workflow` group, keep the N newest and
   delete the older surplus.
3. **`max_total_size_bytes`** – if the artifacts still surviving rules 1–2 exceed
   the byte budget, evict the **oldest survivors first** until the retained total
   fits.

Reasons accumulate (an artifact can be deleted by more than one rule), and every
sort uses stable tie-breaks (creation time → run id → name) so output is
deterministic regardless of input ordering.

## Usage

```bash
python3 artifact_cleanup.py \
  --artifacts fixtures/artifacts.json \
  --policy   fixtures/policy.json \
  --dry-run \
  --now 2026-06-28T12:00:00Z      # optional: freeze the reference time
# --format json   for machine-readable output
# --output FILE   to also write the plan to a file
```

The text output ends with a single machine-parseable marker line, e.g.:

```
RESULT total=4 retained=2 deleted=2 reclaimed=3000 retained_bytes=7000 total_bytes=10000
```

Exit codes: `0` success, `2` on a user error (missing/invalid file, bad data),
which is reported with a meaningful message on stderr.

## Tests

```bash
python3 -m pytest tests/            # everything (the act tests need Docker)
python3 -m pytest tests/ --ignore=tests/test_workflow_act.py   # fast subset
```

The unit tests drove the design one failing test at a time. Per the task, the
**end-to-end** validation of behaviour runs *through the pipeline*: each of the
three cases in `test_workflow_act.py` builds a throwaway git repo with that
case's fixtures, runs `act push` in a container, appends the output to
`act-result.txt`, and asserts the exact `RESULT` values plus that every job
reports "Job succeeded".
