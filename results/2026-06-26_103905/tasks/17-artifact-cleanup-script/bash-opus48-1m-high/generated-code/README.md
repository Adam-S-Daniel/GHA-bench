# Artifact Cleanup

A Bash tool that applies retention policies to a list of CI artifacts (mock
data) and prints a deterministic deletion plan.

## Script

`artifact-cleanup.sh <artifacts-file>` reads TAB-separated records of
`name  size_bytes  created  workflow_run_id` (`created` may be epoch seconds or
an ISO-8601 timestamp) and applies, in a fixed order:

1. `--max-age-days N` — delete artifacts older than N days.
2. `--keep-latest N` — per workflow run, keep only the N most-recent artifacts.
3. `--max-total-size N` — keep surviving artifacts under N total bytes by
   deleting the oldest survivors first.

Other options: `--now TIMESTAMP` (reference time, for deterministic runs),
`--dry-run` (labels the plan DRY RUN), `-h/--help`.

The script never touches a real store — it only computes and prints a plan plus
a summary line: `SUMMARY total=.. retained=.. deleted=.. reclaimed_bytes=..`.

```bash
./artifact-cleanup.sh --now 2026-06-27T00:00:00Z \
    --max-age-days 30 --keep-latest 1 --max-total-size 10000 --dry-run \
    ci-fixtures/case1-combined/artifacts.tsv
```

## Tests (TDD, bats-core)

- `test/artifact-cleanup.bats` — unit tests written red/green during development.
- `test/workflow.bats` — pipeline integration tests: builds an isolated git
  repo and runs the GitHub Actions workflow through `act`, then asserts the
  exact known-good plan for every fixture case. All output is captured to
  `act-result.txt`.

```bash
bats test/            # runs everything (workflow.bats invokes act)
```

## CI

`.github/workflows/artifact-cleanup-script.yml` lints the scripts (`bash -n`,
shellcheck) and runs `ci/run-cases.sh`, which executes the cleanup over every
fixture under `ci-fixtures/` and verifies the expected output. Triggers: push,
pull_request, schedule, workflow_dispatch.
