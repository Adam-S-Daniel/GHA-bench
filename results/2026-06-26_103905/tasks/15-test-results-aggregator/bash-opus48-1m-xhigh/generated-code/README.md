# Test Results Aggregator

A Bash tool that parses test result files in **JUnit XML** and **JSON** formats,
aggregates them across many files (simulating a CI matrix build), computes
totals (passed / failed / skipped / duration), detects **flaky tests** (tests
that both passed and failed across runs), and renders a Markdown summary
suitable for a GitHub Actions job summary.

## Files

| Path | Purpose |
| :--- | :--- |
| `aggregate.sh` | The aggregator. Parses inputs, computes totals + flaky tests, prints Markdown. |
| `test/aggregate.bats` | Red/green TDD unit tests for `aggregate.sh` (also run inside CI via `act`). |
| `test/workflow.bats` | Workflow structure tests + actionlint check + `act-result.txt` verification. |
| `test/fixtures/` | Sample JUnit XML / JSON result files used as a matrix build. |
| `.github/workflows/test-results-aggregator.yml` | The CI workflow that runs the aggregator. |
| `run-act-tests.sh` | End-to-end harness: runs each test case through the workflow via `act`. |
| `act-result.txt` | Captured `act` output for every test case (generated artifact). |

## Usage

```bash
# Aggregate explicit files
./aggregate.sh test/fixtures/junit-suite-a.xml test/fixtures/results-suite-c.json

# Aggregate every *.xml / *.json under a directory (matrix build)
./aggregate.sh test/fixtures/

# Write the summary to a file and fail the run if any test failed
./aggregate.sh --output summary.md --fail-on-failure test/fixtures/
```

### Input formats

**JUnit XML** — `<testsuite>`/`<testsuites>` with `<testcase>` elements. A child
`<failure>` or `<error>` marks a failure; `<skipped>` marks a skip; otherwise the
case passed. Duration comes from the `time` attribute.

**JSON**:

```json
{
  "tests": [
    { "classname": "math.Calc", "name": "test_add", "status": "passed", "duration": 0.09 }
  ]
}
```

`status` is one of `passed | failed | skipped`; `duration` is seconds.

## Running the tests

```bash
# 1. Unit + structure tests directly with bats
bats test/aggregate.bats

# 2. End-to-end through the GitHub Actions workflow via act
#    (writes act-result.txt; runs 3 test cases, one `act push` each)
./run-act-tests.sh all

# 3. Workflow structure + act-artifact verification
bats test/workflow.bats

# Or everything that does not need act:
bats test/
```

`run-act-tests.sh` must run **before** `test/workflow.bats`, because the latter
verifies the `act-result.txt` artifact the harness produces.

## How "all tests run through act"

The workflow's `Run bats unit tests` step executes the *entire*
`test/aggregate.bats` suite inside the `act` container, so every unit test case
runs through the pipeline. On top of that, `run-act-tests.sh` drives three
distinct fixture scenarios end-to-end through `act push` and asserts on the
exact aggregate values each one produces.
