# Test Results Aggregator

Parses test result files in **JUnit XML** and **JSON** formats, aggregates them
across the multiple files of a matrix build, computes totals
(passed / failed / skipped / duration), flags **flaky** tests (passed in some
runs, failed in others), and renders a Markdown summary for a GitHub Actions
job summary.

Built test-first (red/green TDD) — see the cycle markers in
`tests/test_aggregator.py`. The aggregator itself uses **only the Python
standard library**.

## Layout

| Path | Purpose |
| --- | --- |
| `aggregator.py` | The aggregator: parsers, aggregation, flaky detection, Markdown renderer, CLI. |
| `tests/test_aggregator.py` | TDD unit suite (15 tests). |
| `fixtures/` | Documented sample JUnit XML + JSON inputs. |
| `test-results/` | Default matrix results the workflow aggregates. |
| `.github/workflows/test-results-aggregator.yml` | CI pipeline that runs the tests and the aggregator. |
| `harness/` | Workflow validation: actionlint, YAML structure, and per-case `act` runs. |

## Usage

```bash
# Aggregate every result file in a directory into a Markdown report on stdout.
python3 aggregator.py test-results

# In CI, also append the report to the job summary:
python3 aggregator.py test-results --summary-file "$GITHUB_STEP_SUMMARY"

# Exit non-zero if any aggregated test failed (default: aggregation always 0).
python3 aggregator.py test-results --fail-on-failure
```

### Input formats

* **JUnit XML** — standard `<testsuites>/<testsuite>/<testcase>` with
  `<failure>`, `<error>` or `<skipped>` children.
* **JSON** — `{"tests": [{"classname", "name", "status", "duration"}, ...]}`.
  Status spellings (`pass`/`ok`/`error`/`ignored`/...) are normalized.

## Tests

```bash
python3 -m pytest tests/ -v                     # unit tests (fast)
python3 -m pytest harness/ -v -s                # workflow + act validation (slow)
```

The act harness writes every run's output to `act-result.txt`, asserts each
case exits 0, that every job reports "Job succeeded", and that the aggregator
emits the exact known-good totals/flaky lines for that fixture input.
