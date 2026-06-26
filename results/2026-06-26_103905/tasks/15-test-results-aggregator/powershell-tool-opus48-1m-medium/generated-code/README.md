# Test Results Aggregator (PowerShell)

Parses test result files in **JUnit XML** and **JSON** formats, aggregates them
across many files (a CI matrix build), computes totals, detects **flaky tests**
(passed in some runs, failed in others), and renders a Markdown summary suitable
for a GitHub Actions job summary.

## Files

| File | Purpose |
| --- | --- |
| `TestResultsAggregator.ps1` | The tool: parsers, aggregation, flaky detection, Markdown rendering. Dot-sourceable as a library or runnable as a CLI. |
| `TestResultsAggregator.Tests.ps1` | Pester unit tests (written test-first, red/green TDD). |
| `Workflow.Tests.ps1` | Pester tests asserting the workflow's structure and that actionlint passes. |
| `fixtures/` | Sample result files: two JUnit XML runs + one JSON run (a simulated 3-leg matrix). |
| `.github/workflows/test-results-aggregator.yml` | CI workflow that runs the Pester tests, then aggregates fixtures and publishes a job summary. |
| `run-act-tests.ps1` | Integration harness: runs every test case end-to-end through the workflow via `act`, asserting exact aggregate values. |
| `act-result.txt` | Captured `act` output for all integration cases (generated artifact). |

## Usage

```powershell
# Aggregate a directory of result files and write a Markdown summary.
./TestResultsAggregator.ps1 -Path ./fixtures -OutputPath test-summary.md
```

When `$GITHUB_STEP_SUMMARY` is set (inside GitHub Actions), the summary is also
appended to the job summary automatically.

## Testing

```powershell
# Unit + workflow-structure tests
Invoke-Pester -Path ./TestResultsAggregator.Tests.ps1,./Workflow.Tests.ps1

# Full end-to-end through the GitHub Actions pipeline via act
pwsh -File ./run-act-tests.ps1
```

## Supported formats

- **JUnit XML** — `<testcase>` elements; `<failure>`/`<error>` → failed,
  `<skipped>` → skipped, otherwise passed.
- **JSON** — `{ "tests": [ { name, suite, status, duration } ] }` (or a bare
  array). Status strings are normalized (e.g. `pass`/`success` → `passed`).

A test is **flaky** when, grouped by `suite::name`, it recorded at least one
`passed` and at least one `failed` outcome across the aggregated runs.
