# Test Results Aggregator (PowerShell)

Parses test result files in **JUnit XML** and **JSON** formats, aggregates them
across many files (simulating a CI matrix build), computes totals
(passed / failed / skipped / duration), identifies **flaky tests** (passed in
some runs, failed in others), and renders a **Markdown summary** suitable for a
GitHub Actions job summary.

## Layout

| Path | Purpose |
| --- | --- |
| `src/TestResultsAggregator.psm1` | Core module: parsers, aggregation, flaky detection, Markdown rendering. |
| `Invoke-Aggregator.ps1` | CLI entry point. Reads a directory of result files and emits the summary. |
| `tests/TestResultsAggregator.Tests.ps1` | Pester **unit** tests (built red/green via TDD). |
| `tests/Workflow.Structure.Tests.ps1` | Static workflow checks (YAML shape, file refs, actionlint). |
| `tests/Workflow.Act.Tests.ps1` | End-to-end tests that run the workflow through `act`. |
| `fixtures/` | Standalone sample files, one per supported format. |
| `test-results/` | Default input the workflow aggregates on a plain `push`. |
| `.github/workflows/test-results-aggregator.yml` | The CI workflow. |

## Supported input formats

**JUnit XML** — a `<testcase>` is `Failed` if it has a `<failure>`/`<error>`
child, `Skipped` if it has a `<skipped>` child, otherwise `Passed`. The
`classname` attribute is read as the suite name and `time` as the duration.

**JSON** — a top-level `tests` array, each item with `name`, `suite`, `status`
and `duration`. Status spellings (`pass`/`PASS`/`ok`, `fail`/`error`,
`skip`/`ignored` …) are normalized to `Passed`/`Failed`/`Skipped`.

All inputs become one normalized shape, so formats can be mixed freely:

```text
{ Name; Suite; Status (Passed|Failed|Skipped); Duration (seconds); Source }
```

A test is **flaky** when, grouped by `Suite` + `Name` across all files, it has at
least one `Passed` and at least one `Failed` result.

## Usage

```powershell
# Aggregate a directory of result files and write a Markdown summary.
./Invoke-Aggregator.ps1 -InputPath test-results -OutputPath summary.md
```

Under GitHub Actions the script also appends the summary to
`$GITHUB_STEP_SUMMARY`. It is a *reporter*: it exits `0` even when tests failed,
so it can publish a summary without failing the job (pass `-FailOnFailure` to
change that).

## Running the tests

```powershell
# Fast unit + structure tests (no Docker needed)
Invoke-Pester -Path tests/TestResultsAggregator.Tests.ps1,tests/Workflow.Structure.Tests.ps1

# End-to-end tests through act (needs Docker + act). Writes act-result.txt.
Invoke-Pester -Path tests/Workflow.Act.Tests.ps1

# Everything
Invoke-Pester -Path tests
```

## Methodology

The module was built with red/green TDD: every function in
`TestResultsAggregator.psm1` started as a failing Pester test, followed by the
minimum implementation to make it pass. The `act` harness exercises the *exact
same workflow* GitHub would run, asserting on the precise aggregated values for
each fixture (e.g. `passed=4 failed=3 skipped=1 total=8 duration=2.62` and the
flaky `test_logout` row) and that every job reports `Job succeeded`.
