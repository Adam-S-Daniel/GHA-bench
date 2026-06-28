# Test Results Aggregator

Parses test result files in **JUnit XML** and **JSON** formats, aggregates them
across multiple files (simulating a matrix build), computes totals
(passed / failed / skipped / duration), detects **flaky** tests (passed in some
runs, failed in others), and renders a markdown summary suitable for a GitHub
Actions job summary.

## Usage

```bash
python3 aggregator.py fixtures/run1-junit.xml fixtures/run2-results.json
# or write to a file:
python3 aggregator.py -o summary.md fixtures/*.xml fixtures/*.json
```

When `GITHUB_STEP_SUMMARY` is set (i.e. inside Actions) the markdown is also
appended to the job summary automatically.

## Layout

| Path | Purpose |
| ---- | ------- |
| `aggregator.py` | Parsers, aggregation, flaky detection, markdown, CLI |
| `fixtures/` | Sample JUnit XML + JSON result files |
| `tests/test_aggregator.py` | Unit tests (red/green TDD) for every function + the CLI |
| `tests/test_workflow_act.py` | Workflow structure tests + end-to-end runs through `act` |
| `.github/workflows/test-results-aggregator.yml` | CI pipeline that runs the script |

## Approach

Built test-first (red/green TDD): each function was specified by a failing test
before being implemented. Every parsed test is normalised into a `TestCase`
record, so aggregation/flaky-detection/rendering are format-agnostic. JUnit
`<error>` folds into `failed`; JSON status aliases (`pass`, `FAIL`, `skip`, ...)
are normalised. Errors are raised with the offending file name for actionable CI
logs.

## Testing

```bash
python3 -m pytest tests/ -v
```

The `act`-driven tests build a throwaway git repo per case, run
`act push --rm --pull=false`, append output to `act-result.txt`, and assert on
exact expected totals/flaky sets. They skip automatically if `act`/Docker are
absent.
