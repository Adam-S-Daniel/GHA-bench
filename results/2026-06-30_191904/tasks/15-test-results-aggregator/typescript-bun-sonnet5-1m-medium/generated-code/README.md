# test-results-aggregator

Parses JUnit XML and JSON test result files, aggregates totals across multiple
files (simulating matrix build legs), detects flaky tests (pass in some runs,
fail in others), and renders a markdown summary for a GitHub Actions job
summary.

## Install

```bash
bun install
```

## Test

```bash
bun test
```

## Run

```bash
bun run src/aggregator.ts <resultsDir> [--strict]
```

- `resultsDir` — directory of `*.xml` (JUnit) / `*.json` result files. Defaults to `test-results`.
- `--strict` — exit with code 1 if any test failed (fails the CI job).

Writes markdown to stdout, and appends it to `$GITHUB_STEP_SUMMARY` when set.

## Layout

- `src/types.ts` — shared types
- `src/parsers/junit.ts` — JUnit XML parser
- `src/parsers/json.ts` — JSON result parser
- `src/aggregate.ts` — totals + flaky test detection
- `src/report.ts` — markdown summary renderer
- `src/loadResults.ts` — directory scanning / format auto-detection
- `src/aggregator.ts` — CLI entrypoint
- `fixtures/` — sample test result files
- `.github/workflows/test-results-aggregator.yml` — CI workflow
