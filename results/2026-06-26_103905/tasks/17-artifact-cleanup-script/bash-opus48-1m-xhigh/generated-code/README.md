# Artifact Cleanup Script

A dependency-free Bash tool that applies retention policies to a list of build
artifacts, produces a deletion plan, and prints a summary (space reclaimed,
retained vs. deleted). Supports a dry-run mode and JSON output. Built with
red/green TDD and wired into a GitHub Actions maintenance workflow.

## Files

| Path | Purpose |
|------|---------|
| `artifact-cleanup.sh` | The policy engine (pure Bash + coreutils `date`). |
| `test/artifact-cleanup.bats` | Unit tests for the script logic (TDD spec). |
| `test/workflow.bats` | Workflow structure tests + `act` integration harness. |
| `test/fixtures/case{A,B,C}.{txt,env}` | Inventory + policy fixtures per case. |
| `fixtures/artifacts.txt`, `fixtures/policy.env` | Default sample used by the workflow. |
| `.github/workflows/artifact-cleanup-script.yml` | CI pipeline that runs the tool. |
| `act-result.txt` | Captured output of every `act` test case (generated artifact). |

## Input format

One artifact per line, pipe-delimited. Blank lines and `#` comments are ignored:

```
name|size_bytes|created_date|workflow_run_id
build-logs|1048576|2026-06-27|5001
```

`created_date` is anything GNU `date -d` understands (e.g. `2026-06-01` or
`2026-06-01T12:00:00Z`). `workflow_run_id` is the grouping key for keep-latest.

## Retention policies

Each policy is optional and they are applied in this order:

1. **`--max-age-days N`** — delete artifacts strictly older than `N` days.
2. **`--keep-latest N`** — within each `workflow_run_id`, keep the `N` newest
   still-retained artifacts; delete the rest.
3. **`--max-total-size N`** — if retained artifacts still exceed `N` bytes,
   delete the oldest retained artifacts until they fit.

An artifact deleted by an earlier policy keeps that policy as its reason.

## Usage

```bash
# Text plan, using a 30-day age policy and a fixed reference date
./artifact-cleanup.sh --input fixtures/artifacts.txt --now 2026-06-28 --max-age-days 30

# Read all policy settings from a config file (CLI flags override them)
./artifact-cleanup.sh --config fixtures/policy.env --input fixtures/artifacts.txt

# Preview only — perform no deletions
./artifact-cleanup.sh --config fixtures/policy.env --input fixtures/artifacts.txt --dry-run

# Machine-readable output
./artifact-cleanup.sh --config fixtures/policy.env --input fixtures/artifacts.txt --format json
```

`--config` reads `KEY=VALUE` lines (`MAX_AGE_DAYS`, `KEEP_LATEST`,
`MAX_TOTAL_SIZE`, `NOW`, `DRY_RUN`, `FORMAT`, `INPUT`). A fixed `--now` makes
age-based output deterministic, which is what the tests rely on.

## Testing

```bash
bats test/artifact-cleanup.bats   # fast unit tests (run the script directly)
bats test/workflow.bats           # YAML structure + actionlint + act integration
```

The workflow harness builds an isolated git repo per fixture case, runs the
pipeline with `act push --rm`, appends the output to `act-result.txt`, and
asserts the exact expected counts/bytes and that every job reports
`Job succeeded`.
