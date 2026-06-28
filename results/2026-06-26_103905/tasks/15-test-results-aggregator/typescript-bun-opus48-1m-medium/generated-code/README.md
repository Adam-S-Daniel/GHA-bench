# Test Results Aggregator

Parses test result files (JUnit XML + JSON), aggregates them across a matrix
build, computes totals, identifies flaky tests, and renders a markdown summary
suitable for a GitHub Actions job summary.

## Layout

- `src/types.ts` — shared domain types (`TestResult`, `Totals`, `FlakyTest`, …).
- `src/parser.ts` — `parseJUnitXml`, `parseJsonResults`, and `parseContent`
  (extension-based dispatch). Dependency-free XML tokenizer.
- `src/aggregator.ts` — `aggregate()`: folds many parsed files into totals and a
  flaky-test report. A test is *flaky* when it both passed and failed across runs.
- `src/summary.ts` — `renderSummary()`: GitHub-flavored markdown.
- `src/cli.ts` — entry point: reads files, aggregates, writes
  `$GITHUB_STEP_SUMMARY`, exits nonzero on failure (`--no-fail` to suppress).
- `fixtures/` — sample matrix-shard result files + `expected.txt` snapshot.
- `tests/` — Bun tests (TDD, red/green) plus `act-harness.ts` (E2E via `act`).

## Usage

```bash
bun test                                          # unit tests
bun run src/cli.ts fixtures/shard-1.xml fixtures/shard-2.json fixtures/shard-3.xml
bun run tests/act-harness.ts                      # run the workflow through act
```

## CI

`.github/workflows/test-results-aggregator.yml` runs the unit tests, then a
dependent job aggregates the fixtures into the job summary and verifies the
output against `fixtures/expected.txt`. Validated with `actionlint` and
exercised end-to-end with `nektos/act` (see `act-result.txt`).
