# Test Results Aggregator

Parses test result files in **JUnit XML** and **JSON** formats, aggregates them
across multiple files (simulating a CI matrix build), computes totals
(passed/failed/skipped/duration), identifies **flaky tests** (passed in some
runs, failed in others), and renders a **markdown summary** suitable for a
GitHub Actions job summary.

Written in **TypeScript**, run with **Bun**.

## Layout

| Path | Purpose |
| --- | --- |
| `src/types.ts` | Shared domain types (`TestCase`, `TestRun`, `Totals`, `FlakyTest`, …). |
| `src/parser.ts` | Format parsers: JUnit XML + JSON → normalized `TestRun`. |
| `src/aggregator.ts` | Roll-up totals + flaky-test detection across runs. |
| `src/summary.ts` | Renders an `AggregateResult` to GitHub-flavored markdown. |
| `src/loader.ts` | Filesystem layer: resolve paths → parse → aggregate. |
| `src/index.ts` | CLI entry point (writes to stdout + `$GITHUB_STEP_SUMMARY`). |
| `fixtures/` | Sample result files (a 3-leg matrix with one flaky test). |
| `tests/` | Unit tests (`bun test`). |
| `harness/run-act.ts` | Integration harness — runs the workflow through `act`. |
| `.github/workflows/test-results-aggregator.yml` | CI workflow. |

## Usage

```bash
# Aggregate every result file in a directory:
bun run src/index.ts fixtures

# Or pass individual files / multiple paths:
bun run src/index.ts results/ubuntu.xml results/macos.json

# Gate the pipeline (exit 1) when any test failed:
bun run src/index.ts fixtures --fail-on-failure
```

The aggregated markdown is printed to stdout and, when `$GITHUB_STEP_SUMMARY`
is set (i.e. inside GitHub Actions), appended to the job summary page.

## Supported input formats

- **JUnit XML** — the standard `<testsuites>/<testsuite>/<testcase>` shape. A
  case's status is inferred from a child `<failure>`/`<error>` (failed),
  `<skipped>` (skipped), or neither (passed).
- **JSON** — either `{ "tests": [ … ] }` or a bare array. Each entry needs a
  `name`; `suite`/`classname`, `status`, and `duration`/`time` are optional.
  Common status aliases are normalized (`pass`→`passed`, `fail`→`failed`, …).

## Testing

```bash
bun test                    # unit tests (parser, aggregator, summary, loader, CLI, workflow)
bun run harness/run-act.ts  # full integration: runs the workflow via act (3 cases)
```

The act harness builds a throwaway git repo per case, injects that case's
fixture data, runs `act push --rm`, appends the output to `act-result.txt`,
and asserts the aggregator produced the EXACT known-good numbers.

## Development methodology

Built test-first (red → green → refactor): each module had a failing `bun test`
spec written before its implementation.
