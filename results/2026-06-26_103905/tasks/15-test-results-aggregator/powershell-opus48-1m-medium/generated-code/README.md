# Test Results Aggregator (PowerShell)

Parses test result files in **JUnit XML** and **JSON**, aggregates them across
multiple files (simulating a matrix build), computes totals
(passed / failed / skipped / duration), identifies **flaky** tests (passed in
some runs, failed in others), and renders a markdown summary suitable for a
GitHub Actions job summary.

## Layout

| Path | Purpose |
| --- | --- |
| `src/TestResultsAggregator.psm1` | Core module (parsers, aggregation, markdown). |
| `Invoke-Aggregation.ps1` | CLI entry point used by CI. |
| `fixtures/` | Sample result files for the unit tests (fixed). |
| `results-input/` | Default result files the workflow aggregates. |
| `tests/TestResultsAggregator.Tests.ps1` | Pester unit tests (red/green TDD). |
| `tests/Workflow.Tests.ps1` | Workflow-structure + actionlint tests. |
| `tests/Run-ActHarness.ps1` | Runs the workflow through `act` for 3 cases. |
| `.github/workflows/test-results-aggregator.yml` | CI workflow. |

## Approach

Each test case is normalised to a `{ Name, Suite, Status, Duration }` object.
A test is keyed by `Suite.Name`; it is **flaky** when its set of statuses across
all runs contains both `Passed` and `Failed`. Errors (missing files, malformed
XML/JSON, unsupported extensions, empty input) throw meaningful messages.

Built test-first: every function began as a failing Pester test, then the
minimum code to pass it. See the `Describe` blocks in the test file.

## Running

```pwsh
# Unit + workflow-structure tests
Invoke-Pester -Path tests/TestResultsAggregator.Tests.ps1, tests/Workflow.Tests.ps1

# Aggregate locally
./Invoke-Aggregation.ps1 -InputPath ./results-input -OutputPath ./test-summary.md

# Full pipeline through act (writes act-result.txt)
pwsh -File tests/Run-ActHarness.ps1
```

## CI

The workflow runs the Pester suite (`unit-tests` job), then aggregates results
and publishes the summary to `$GITHUB_STEP_SUMMARY` (`aggregate` job, gated on
`needs: unit-tests`). All `run:` steps use `shell: pwsh`. Validated with
`actionlint` and executed locally via `nektos/act`.
