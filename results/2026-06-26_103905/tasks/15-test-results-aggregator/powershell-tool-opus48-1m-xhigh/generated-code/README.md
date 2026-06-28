# Test Results Aggregator (PowerShell)

Parses test result files in **JUnit XML** and **JSON** formats, aggregates them
across many files (simulating a matrix build), computes combined totals
(passed / failed / skipped / duration), identifies **flaky tests** (passed in
some runs, failed in others), and renders a Markdown summary suitable for a
GitHub Actions job summary.

## Layout

| Path | Purpose |
| ---- | ------- |
| `src/TestResultsAggregator.psm1` | The module: parsers, aggregation, flaky detection, Markdown rendering. |
| `Invoke-Aggregator.ps1` | CLI entry point used by the workflow. Writes Markdown to `$GITHUB_STEP_SUMMARY` and prints machine-readable totals. |
| `fixtures/` | Sample test reports (`run1-junit.xml`, `run2-results.json`) — a two-leg matrix containing one flaky test. |
| `tests/TestResultsAggregator.Tests.ps1` | Pester unit tests for the module (red/green TDD). |
| `tests/Workflow.Tests.ps1` | Workflow structure tests + the `act` end-to-end harness. |
| `.github/workflows/test-results-aggregator.yml` | The CI pipeline (unit tests gate → aggregate + publish summary). |
| `act-result.txt` | Captured output of every workflow run executed through `act`. |

## Public functions

- `ConvertFrom-JUnitXml -Path <file>` — parse a JUnit XML report.
- `ConvertFrom-TestJson -Path <file>` — parse a JSON report (`{tests:[...]}` or a bare array).
- `Import-TestResultFile -Path <file>` — dispatch by extension and tag each result with its run (source file).
- `Get-TestTotals -Result <objs>` — combined Passed/Failed/Skipped/Total/Duration.
- `Get-FlakyTest -Result <objs>` — tests that both passed and failed across runs.
- `New-TestSummaryMarkdown -Result <objs>` — render the GitHub-flavored Markdown summary.
- `Invoke-TestResultAggregation -Path <dir|files>` — end-to-end aggregation returning one report object.

All formats are normalized to a common shape: `Name`, `Status`
(`Passed`/`Failed`/`Skipped`), `Duration` (seconds), `Suite`, `Run`.

## Usage

```powershell
# Aggregate every .xml/.json report under ./fixtures and write the job summary.
./Invoke-Aggregator.ps1 -Path ./fixtures
```

Stable, greppable lines are printed for CI to assert on:

```
AGG_TOTALS passed=5 failed=1 skipped=2 total=8 duration=0.71 runs=2
AGG_FLAKY_COUNT 1
AGG_FLAKY_TEST Calc.divide passed=1 failed=1
```

By design the script exits `0` even when aggregated results contain failing
tests (its job is to *report*). Pass `-FailOnTestFailure` to gate a build on
failures.

## Testing

```powershell
# Module unit tests + workflow structure checks (fast, no Docker):
Invoke-Pester -Path ./tests -ExcludeTagFilter Act

# Full end-to-end harness (runs the workflow through nektos/act; needs Docker):
Invoke-Pester -Path ./tests -Tag Act
```

The `Act`-tagged tests build an isolated temporary git repo per case, run
`act push --rm`, append the full output to `act-result.txt`, and assert on exact
expected values (totals, flaky tests, `Job succeeded`, exit code 0).

## How flaky detection works

Results are grouped by fully-qualified test name across all runs. A test is
flaky only when it was observed both **passing** and **failing**. A test that
fails in every run is a *stable failure*, not flaky, and is deliberately not
reported as such.
