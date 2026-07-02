# Test Results Aggregator (TypeScript + Bun)

Parses test result files in **JUnit XML** and **JSON** formats, aggregates them
across multiple files (simulating a matrix build), computes totals
(passed / failed / skipped / duration), detects **flaky tests** (passed in some
runs, failed in others), and renders a markdown summary suitable for a GitHub
Actions job summary (`$GITHUB_STEP_SUMMARY`).

## Usage

```bash
bun run src/cli.ts <results-dir> [--out summary.md]
# e.g. against the bundled sample fixtures:
bun run src/cli.ts fixtures/case1
```

Output: a machine-readable `AGGREGATE_RESULT ...` line, one `FLAKY_TEST ...`
line per flaky test, then the markdown summary. When `$GITHUB_STEP_SUMMARY` is
set (GitHub Actions / act), the markdown is appended to the job summary.

## Layout

| Path | Purpose |
| --- | --- |
| `src/types.ts` | Shared domain types (`TestRun`, `Totals`, `FlakyTest`, ...) |
| `src/parsers/junit.ts` | JUnit XML parser (dependency-free, JUnit subset) |
| `src/parsers/json.ts` | JSON results parser (simple documented schema) |
| `src/aggregate.ts` | Cross-run aggregation + flaky/failed classification |
| `src/markdown.ts` | GitHub-flavored markdown summary renderer |
| `src/cli.ts` | CLI: discovery, orchestration, `GITHUB_STEP_SUMMARY` |
| `tests/` | Bun test suite (written test-first, red/green TDD) |
| `fixtures/case1` | Sample matrix output: 1 flaky test + 1 real failure |
| `fixtures/case2` | Sample matrix output: fully green |
| `.github/workflows/test-results-aggregator.yml` | CI pipeline (unit-tests → aggregate) |
| `scripts/run-act-tests.ts` | End-to-end harness: runs each case through `act` |

## Flaky-test semantics

A test's identity across runs is `suite > name`. A test is **flaky** if it
passed in at least one run *and* failed in at least one run. A test that failed
and never passed is a **failing test**. Skips never affect flakiness
(skipped-then-passed is normal platform-conditional behavior).

## Testing

```bash
bun test                          # unit + workflow-structure tests
actionlint .github/workflows/test-results-aggregator.yml
bun run scripts/run-act-tests.ts  # every case end-to-end through act (Docker)
```

The act harness writes all workflow logs to `act-result.txt` and asserts exact
known-good values (e.g. `AGGREGATE_RESULT total=10 passed=6 failed=2 skipped=2
duration=4.90s flaky=1` for `fixtures/case1`) plus a `Job succeeded` marker per
job.

## TDD history

Each module was built red/green: the test file was written first and run to a
failing state (module-resolution error, then assertion failures), the minimal
implementation added, then refactored with tests green. See the header comment
in each `tests/*.test.ts` for the cycle it drove.
