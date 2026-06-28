# Test Results Aggregator (PowerShell)

Parses test result files in **JUnit XML** and **JSON** formats, aggregates them across
a matrix build, computes totals (passed / failed / skipped / duration), detects **flaky
tests** (passed in some runs, failed in others), and renders a markdown summary for the
**GitHub Actions job summary**.

## Layout

| Path | Purpose |
| ---- | ------- |
| `TestResultsAggregator.psm1` | Module with all logic (parsers, aggregation, markdown). |
| `Invoke-Aggregator.ps1` | CLI entry point used by the workflow. Writes `$GITHUB_STEP_SUMMARY` + a `KEY=VALUE` metrics block. |
| `.github/workflows/test-results-aggregator.yml` | CI pipeline: `test` job (Pester) → `aggregate` job (`needs: test`). |
| `fixtures/` | Default matrix-build input the workflow aggregates (2 JUnit XML + 1 JSON). |
| `tests/TestResultsAggregator.Tests.ps1` | Pester unit tests (also run inside the pipeline). |
| `tests/Workflow.Tests.ps1` | Workflow structure tests + the `act` end-to-end harness (tag `Act`). |
| `tests/fixtures/` | Stable fixtures for unit tests + extra act case (`caseB/`). |

## How flaky detection works

Each parsed test case is normalized to a common shape with a stable `TestId`
(`ClassName.Name`). Results are grouped by `TestId` across all files; a test is **flaky**
when its group contains **both** a `passed` and a `failed` outcome. A test that fails in
every run is *consistently failing*, not flaky.

## Running

```pwsh
# Aggregate a directory of result files (markdown + metrics to stdout):
./Invoke-Aggregator.ps1 -Path fixtures -ShowSummary

# Fast unit + structure tests (no Docker):
Invoke-Pester ./tests/TestResultsAggregator.Tests.ps1
Invoke-Pester ./tests/Workflow.Tests.ps1 -ExcludeTagFilter Act

# Full end-to-end run through GitHub Actions via act (writes act-result.txt):
Invoke-Pester ./tests/Workflow.Tests.ps1 -TagFilter Act
```

Every test case is exercised **through the workflow**: the `test` job runs the Pester
suite inside the container, and the `act` harness drives the whole pipeline against two
fixture cases, asserting exact aggregate values and that each job reports
`Job succeeded`. All `act` output is appended (delimited per case) to `act-result.txt`.

## Supported input formats

* **JUnit XML** — `<testsuites>` or bare `<testsuite>` roots. A `<testcase>` is `failed`
  if it has a `<failure>`/`<error>` child, `skipped` if it has `<skipped>`, else `passed`.
* **JSON** — an object with a `tests` array (or a bare array). Each entry: `name`,
  optional `classname`, `status` (common spellings normalized), and `duration`/`time`.

All numeric parsing/formatting uses `InvariantCulture`, so results are stable on runners
with comma decimal separators.
