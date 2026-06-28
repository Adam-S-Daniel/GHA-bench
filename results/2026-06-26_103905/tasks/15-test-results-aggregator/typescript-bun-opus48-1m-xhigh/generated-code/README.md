# Test Results Aggregator

A small, dependency-free TypeScript/Bun tool that parses test-result files in
multiple formats (**JUnit XML** and **JSON**), aggregates them across many files
(simulating a CI **matrix build**), computes totals, detects **flaky tests**, and
emits a Markdown summary suitable for a **GitHub Actions job summary**.

Built test-first (red/green TDD) with Bun's built-in test runner.

## Layout

```
src/
  types.ts        # Shared domain types (the format-agnostic representation)
  parser.ts       # JUnit XML + JSON parsers -> TestRun
  aggregator.ts   # Totals + flaky-test detection
  markdown.ts     # Markdown summary + machine-readable summary renderers
  cli.ts          # CLI entry point (reads files/dirs, writes job summary)
tests/
  parser.test.ts          # unit
  aggregator.test.ts      # unit
  markdown.test.ts        # unit
  workflow.test.ts        # workflow YAML structure + actionlint
  act.integration.test.ts # end-to-end: runs the workflow through `act`
fixtures/
  sample/    # default 3-leg matrix (XML+XML+JSON), 2 flaky tests, failures
  all-pass/  # all-green 2-leg matrix (XML+JSON), no flaky tests
.github/workflows/test-results-aggregator.yml
```

## Usage

```bash
# Aggregate every .xml / .json file in a directory (default: fixtures/sample):
bun run src/cli.ts fixtures/sample

# Or pass explicit files / multiple directories:
bun run src/cli.ts run-1.xml run-2.xml results-3.json
```

The CLI writes the human-facing Markdown to `$GITHUB_STEP_SUMMARY` when set (so
it shows up as the GitHub Actions job summary) and echoes it to stdout, followed
by a delimited `=== AGGREGATE SUMMARY ===` key=value block used for reliable
CI assertions. It exits `0` whenever aggregation succeeds — failing the *summary*
job on red tests is the responsibility of the test job, not this one.

## Supported input formats

**JUnit XML** — standard `<testsuites>`/`<testsuite>`/`<testcase>` documents;
`<failure>`/`<error>` mark a case failed, `<skipped>` marks it skipped, and a
self-closing `<testcase/>` is a pass.

**JSON** — either a top-level array of cases or an object with a `tests` array
(plus optional `name`). Each case has `name`, optional `suite`, a `status`
(common synonyms like `pass`/`fail`/`skip`/`error` are normalised), an optional
`duration`/`time`, and an optional `message`.

## Flaky detection

A test (identified by `suite > name`) is **flaky** when, across all aggregated
runs, it both passed at least once and failed at least once. Skips never make a
test flaky.

## Tests

```bash
bun test                 # all unit + workflow-structure tests (act suite skips)
RUN_ACT=1 bun test tests/act.integration.test.ts   # end-to-end through act
```

The act integration suite is guarded by `RUN_ACT` because `act` is slow; running
it (re)generates `act-result.txt`, the captured end-to-end evidence for both the
flaky/failing and all-green scenarios.

## CI

`.github/workflows/test-results-aggregator.yml` runs on push, pull_request, a
weekly schedule, and manual dispatch. It checks out the repo, sets up Bun, runs
the unit suite, then aggregates `fixtures/sample` (override the directory via the
`results_dir` dispatch input or the `RESULTS_DIR` env var) and publishes the
Markdown job summary.
