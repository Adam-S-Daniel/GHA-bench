# Test Results Aggregator

Aggregates test results across multiple result files (simulating a GitHub
Actions matrix build), supporting **JUnit XML** and **JSON** formats, and
emits a markdown summary suitable for `$GITHUB_STEP_SUMMARY`.

## Usage

```sh
./aggregate-test-results.sh <results-dir> [output-file]
```

Reports totals (passed / failed / skipped / duration), **flaky tests**
(passed in some runs, failed in others), and consistently failing tests.

## Design

Each format parser normalizes files into a shared TSV intermediate format
(`id<TAB>status<TAB>duration`); a single awk pass then aggregates and renders
markdown. Adding a new input format only requires a new parser function.

## Files

- `aggregate-test-results.sh` — the aggregator (bash + awk + jq)
- `fixtures/` — mixed-results fixtures: 3 matrix runs, 11 results, one flaky
  test (`suite.test_flaky`), one consistent failure (`suite.test_beta`)
- `fixtures-allpass/` — all-passing fixtures (no flaky tests)
- `test/aggregator.bats` — TDD unit test suite (16 tests)
- `test/workflow.bats` — workflow structure tests (10 tests, incl. actionlint)
- `.github/workflows/test-results-aggregator.yml` — CI workflow: `test` job
  runs the full bats suite, `aggregate` job (needs: test) runs the aggregator
  and publishes the job summary
- `run-act-tests.sh` — end-to-end harness: runs every test case through the
  workflow with `act`, asserts exact expected values, writes `act-result.txt`

## Development (TDD)

Built red/green: failing test first, minimal implementation, refactor —
cycle 1: error handling; cycle 2: JUnit XML parsing/totals; cycle 3: JSON,
cross-file aggregation, flaky detection, markdown rendering.

```sh
bats test/           # run all tests locally
./run-act-tests.sh   # run everything through the workflow via act
```
