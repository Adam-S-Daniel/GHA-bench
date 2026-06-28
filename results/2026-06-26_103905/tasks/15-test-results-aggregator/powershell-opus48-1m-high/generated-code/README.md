# Test Results Aggregator (PowerShell)

Parses test result files in **JUnit XML** and **JSON**, aggregates them across
multiple files (a CI matrix build), computes totals, identifies **flaky tests**
(passed in some runs, failed in others), and renders a markdown summary suitable
for a GitHub Actions job summary.

## Layout

| Path | Purpose |
| --- | --- |
| `TestResultsAggregator.psm1` | Library: parsers, aggregation, flaky detection, markdown rendering |
| `Invoke-Aggregator.ps1` | CLI entry point used by the workflow |
| `fixtures/` | Sample matrix result files (2 JUnit XML + 1 JSON) with a flaky test |
| `Tests/` | Pester unit tests (red/green TDD) for the library + CLI |
| `WorkflowTests/` | Workflow structure tests + `act` end-to-end harness |
| `.github/workflows/test-results-aggregator.yml` | CI pipeline (unit tests -> aggregate) |
| `act-result.txt` | Captured `act` output for every harness case (generated) |

## Usage

```pwsh
# Aggregate a directory of result files and print the markdown summary.
./Invoke-Aggregator.ps1 -Path ./fixtures

# Gate the build (exit non-zero) when any test failed.
./Invoke-Aggregator.ps1 -Path ./fixtures -FailOnFailure
```

Inside GitHub Actions the summary is also appended to `$GITHUB_STEP_SUMMARY`.

## Normalized model

Every parser produces the same record shape so aggregation is format-agnostic:

```
Suite, Name, Status (Passed|Failed|Skipped), Duration (seconds), File
```

A test is **flaky** when, across all matrix runs, it has both a `Passed` and a
`Failed` result (matched by `Suite` + `Name`).

## Running the tests

```pwsh
# Unit tests only (fast)
Invoke-Pester -Path ./Tests

# Everything, including the act end-to-end harness (needs Docker + act)
Invoke-Pester -Path ./Tests,./WorkflowTests
```

The act harness builds an isolated temp git repo per fixture case, runs
`act push --rm`, appends the output to `act-result.txt`, and asserts on exact
expected values. The harness self-skips when `act` is unavailable or when it is
already running inside an act container (`$env:ACT`).
