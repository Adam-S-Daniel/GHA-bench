# Test Results Aggregator

Parses test result files from a matrix build (JUnit XML + JSON), aggregates
totals (passed / failed / skipped / duration), detects **flaky tests** (same
test passed in some runs, failed in others), and renders a markdown summary
for the GitHub Actions job summary. Built test-first with Pester (red/green
TDD — one cycle per Describe block, see `tests/TestResultsAggregator.Tests.ps1`).

## Layout

| Path | Purpose |
| ---- | ------- |
| `src/TestResultsAggregator.psm1` | Module: parsers, aggregation, flaky detection, markdown rendering |
| `scripts/Invoke-Aggregator.ps1` | CLI entry point used by the workflow (`-InputPath <dir> -OutputPath <file>`) |
| `fixtures/` | Sample matrix results: 2 JUnit XML legs + 1 JSON leg, incl. one flaky test |
| `tests/` | Pester suites: module unit tests + workflow structure tests |
| `tests/fixtures/` | Unit-test fixtures (independent of workflow input fixtures) |
| `.github/workflows/test-results-aggregator.yml` | CI workflow: `test` job (Pester) → `aggregate` job (summary) |
| `act-cases/` | Alternative fixture sets for the act harness |
| `run-act-tests.ps1` | End-to-end harness: runs every case through the workflow via `act` |
| `act-result.txt` | Captured act output for all harness cases (generated) |

## Running

```powershell
# Unit + workflow structure tests
Invoke-Pester -Path ./tests

# Aggregate the sample matrix locally
./scripts/Invoke-Aggregator.ps1 -InputPath fixtures -OutputPath summary.md

# Full end-to-end run through GitHub Actions via act (needs Docker)
./run-act-tests.ps1
```

The harness builds a temp git repo per case (project files + that case's
fixtures), runs `act push --rm --pull=false`, appends the output to
`act-result.txt`, and asserts exact expected totals (e.g. `| **Total** | **10** |`,
`**Duration:** 4.25s across 3 result file(s)`, `| Suite.test_flaky | 2 | 1 |`)
plus `Job succeeded` for both jobs.
