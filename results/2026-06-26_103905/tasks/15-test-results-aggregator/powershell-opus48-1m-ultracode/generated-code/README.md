# Test Results Aggregator (PowerShell)

Parses test result files in **JUnit XML** and **JSON** formats, aggregates them
across multiple files (a matrix build), computes totals (passed / failed /
skipped / duration), identifies **flaky tests** (passed in some runs, failed in
others), and renders a **markdown summary** suitable for a GitHub Actions job
summary.

## Layout

| Path | Purpose |
| --- | --- |
| `TestResultsAggregator.ps1` | Library of functions (dot-sourced; defines, runs nothing). |
| `Invoke-Aggregator.ps1` | CLI entry point used by the workflow. |
| `fixtures/` | Sample result files for a 3-leg matrix (the default input). |
| `testcases/case-b/` | A second fixture set (all-passing) for the act harness. |
| `tests/TestResultsAggregator.Tests.ps1` | Pester unit tests for the library (TDD). |
| `tests/Workflow.Tests.ps1` | Workflow structure tests + end-to-end `act` tests. |
| `tests/ActHarness.ps1` | Helpers that run the workflow through `act`. |
| `.github/workflows/test-results-aggregator.yml` | The CI/CD workflow. |
| `act-result.txt` | Captured `act push` output for every test case (artifact). |

## How it works

```
Import-TestResultSet  ->  Get-AggregateSummary  ->  Format-MarkdownSummary
   (read XML/JSON)          (totals + flaky)          (markdown table)
```

A *test result record* is normalized to `{ Run, Suite, Name, FullName, Status,
Duration, Message }`. Records are grouped by `FullName` across runs; a test that
has at least one `Passed` and at least one `Failed` result is **flaky**.

### Supported inputs

* **JUnit XML** — `<testsuites>/<testsuite>/<testcase>`; a `<failure>`/`<error>`
  child means Failed, `<skipped>` means Skipped, otherwise Passed. `time` is the
  duration in seconds.
* **JSON** — either a bare array of test objects, or `{ "run": "...", "tests":
  [ ... ] }`. Each test: `name`, `status` (any common spelling), optional
  `suite`/`classname`, `duration`, `message`.

## Run it

```powershell
# Aggregate the sample fixtures and write a markdown summary file.
./Invoke-Aggregator.ps1 -Path fixtures -OutFile summary.md
```

Inside GitHub Actions / `act`, the markdown is also appended to
`$GITHUB_STEP_SUMMARY`, and the totals are published as step outputs for the
downstream `report` job.

## Test

```powershell
# Unit tests only (fast):
Invoke-Pester ./tests/TestResultsAggregator.Tests.ps1

# Workflow structure tests only (no Docker):
Invoke-Pester ./tests/Workflow.Tests.ps1 -ExcludeTagFilter Act

# Everything, including the end-to-end runs through act (requires Docker):
Invoke-Pester ./tests
```

The `Act`-tagged tests build a temporary git repo per fixture case, run
`act push --rm`, append the output to `act-result.txt`, and assert on exact
expected values (e.g. `passed=12 failed=3 skipped=3 total=18`, three named
flaky tests) plus that every job reports "Job succeeded".

## Design notes

* The aggregator is a **reporter**: it always exits 0 on a successful parse so
  it never fails the build itself. Gating is the test step's job; the workflow's
  `report` job surfaces a `::warning` when flaky tests are present.
* Durations are parsed with the invariant culture so a `.`/`,` locale mismatch
  can't corrupt totals.
* The workflow uses `shell: pwsh` for all PowerShell steps (no `pwsh -File`
  escaping issues in act containers).
