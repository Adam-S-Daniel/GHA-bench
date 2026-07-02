# Test Results Aggregator

Aggregates test result files from a CI matrix build (JUnit XML and JSON),
computes totals (passed / failed / skipped / duration), detects flaky tests
(passed in some matrix jobs, failed in others), and emits a markdown summary
for the GitHub Actions job summary.

## Layout

- `aggregator.py` — parsers, aggregation, flaky detection, markdown, CLI.
  Every parser normalizes into `TestResult(classname, name, status, duration)`;
  everything downstream works on that uniform shape.
- `tests/` — pytest suite, built red/green TDD (one commit per cycle; see
  `git log`). Includes workflow structure tests (`tests/test_workflow.py`).
- `fixtures/` — sample matrix-build results: 2 JUnit XML jobs + 1 JSON job,
  containing one flaky test (`shop.TestCore::test_flaky_network`).
- `.github/workflows/test-results-aggregator.yml` — CI: run unit tests, then
  aggregate `fixtures/` and publish the job summary.
- `harness.py` — end-to-end harness: runs every test case through the workflow
  with `act push --rm` in isolated temp git repos, appends all output to
  `act-result.txt`, and asserts exact expected values.

## Usage

```bash
python3 aggregator.py fixtures --output summary.md   # aggregate a directory
python3 -m pytest tests/ -v                          # unit + structure tests
python3 harness.py                                   # full act e2e run
python3 harness.py --check-only                      # re-assert on saved output
```

Errors (missing files, bad XML/JSON, unknown status/extension) exit 2 with a
message naming the offending file.
