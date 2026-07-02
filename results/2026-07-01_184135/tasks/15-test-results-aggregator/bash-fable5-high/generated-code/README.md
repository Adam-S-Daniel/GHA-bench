# Test Results Aggregator

Aggregates test result files from multiple formats (JUnit XML and JSON)
across multiple files — simulating the shards of a CI matrix build —
computes totals, detects flaky tests, and emits a markdown summary
suitable for a GitHub Actions job summary (`$GITHUB_STEP_SUMMARY`).

Built with red/green TDD using [bats-core](https://github.com/bats-core/bats-core).

## Files

| Path | Purpose |
| ---- | ------- |
| `aggregate-test-results.sh` | The aggregator CLI (pure bash + awk + jq). |
| `tests/aggregator.bats` | Unit + end-to-end tests for the aggregator. |
| `tests/workflow.bats` | Structure tests for the GitHub Actions workflow (YAML shape, referenced paths, actionlint). |
| `fixtures/matrix-flaky/` | Sample matrix results: 2 JUnit XML shards + 1 JSON shard, containing one flaky test (`math.test_div`). |
| `fixtures/all-pass/` | Sample all-green matrix results. |
| `.github/workflows/test-results-aggregator.yml` | CI pipeline: runs the bats suite, then aggregates results and publishes the summary. |
| `run_act_tests.sh` | End-to-end harness that runs every test case through the workflow via `act`, writing output to `act-result.txt`. |

## Usage

```console
$ ./aggregate-test-results.sh [-o OUTPUT_FILE] RESULTS_DIR
```

`RESULTS_DIR` must contain `*.xml` (JUnit) and/or `*.json` result files —
one file per matrix run. The summary goes to stdout, or to `OUTPUT_FILE`
with `-o`. In a workflow:

```yaml
- run: ./aggregate-test-results.sh -o summary.md test-results
- run: cat summary.md >> "$GITHUB_STEP_SUMMARY"
```

### Input formats

**JUnit XML** — standard `<testsuite>`/`<testcase>` documents. A testcase
containing `<failure>` or `<error>` counts as failed; `<skipped>` as
skipped; otherwise passed.

**JSON** — `{"suite": "name", "tests": [{"name": "pkg.test_x",
"status": "passed|failed|skipped", "duration": 1.2}]}` where `name` is the
fully-qualified test id.

### Flaky detection

Records from all files are normalized to `run_id, test_id, status,
duration` tuples. A test is *flaky* when the same `test_id` passed in at
least one run and failed in at least one other run of the matrix.

## Running the tests

```console
$ bats tests/            # unit + workflow-structure tests, directly
$ ./run_act_tests.sh     # every case end-to-end through act (writes act-result.txt)
```
