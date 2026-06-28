# Test Results Aggregator

A TypeScript + [Bun](https://bun.sh) tool that parses test result files in
**JUnit XML** and **JSON** formats, aggregates them across a matrix build,
computes totals, detects **flaky tests** (passed in some runs, failed in
others), and renders a markdown summary suitable for a **GitHub Actions job
summary** (`$GITHUB_STEP_SUMMARY`).

## What it does

- **Parses two formats** and normalises them into one internal model:
  - JUnit XML (`<testsuites>`/`<testsuite>`/`<testcase>` with
    `failure`/`error`/`skipped` markers). Parsed by a small, dependency-free XML
    parser so nothing has to be installed in CI.
  - A flexible JSON schema (`{ "name", "tests": [{ name, suite, status,
    duration, message }] }`, or a bare array of tests).
- **Aggregates across runs** (one file == one matrix leg): totals for passed /
  failed / skipped / total / duration.
- **Detects flaky tests**: a test that *passed in at least one run and failed in
  at least one other run*. A consistently-failing or skipped test is not flaky.
- **Renders markdown**: an overall verdict, a totals table, a flaky-tests table,
  and a per-run breakdown. No emoji, so the exact lines are easy to assert on.

## Layout

```
src/
  types.ts      Shared interfaces / types
  parsers.ts    JSON + JUnit-XML parsers (incl. a minimal XML parser) + dispatcher
  aggregate.ts  Totals + flaky-test detection
  markdown.ts   GitHub job-summary markdown renderer
  cli.ts        CLI entry point (stdout + $GITHUB_STEP_SUMMARY + $GITHUB_OUTPUT)
tests/          bun test suites (TDD red/green), incl. workflow + act harness
fixtures/
  sample/       A 3-leg matrix with a flaky test (default workflow input)
  all-green/    An all-passing scenario (used by the act harness)
.github/workflows/test-results-aggregator.yml
```

## Usage

```bash
# Aggregate a directory of result files (default fixtures):
bun run src/cli.ts fixtures/sample

# Or pass explicit files:
bun run src/cli.ts run1.xml run2.json

# Options:
#   --fail-on-failure   exit 1 if any test failed (default: always exit 0)
#   --json              also print the full aggregate as JSON
#   -h, --help          usage
```

By default the tool is a **reporter**: it exits `0` even when tests failed, so it
never breaks the build that runs it. Use `--fail-on-failure` to opt into a
non-zero exit.

When run inside GitHub Actions it appends the markdown report to
`$GITHUB_STEP_SUMMARY` and writes `key=value` pairs (`passed`, `failed`,
`flaky`, ...) to `$GITHUB_OUTPUT` for dependent steps/jobs.

## Tests

```bash
bun test                       # all unit + structure tests (Docker-free, fast)
RUN_ACT=1 bun test tests/act-harness.test.ts   # run the workflow through `act`
```

- **Unit tests** (`parsers`, `aggregate`, `markdown`, `cli`) drive the logic via
  red/green TDD.
- **Structure tests** (`workflow.test.ts`) parse the workflow YAML, check its
  triggers/jobs/steps, verify it references scripts that exist, and assert
  `actionlint` passes.
- **The act harness** (`act-harness.test.ts`, gated behind `RUN_ACT=1`) runs the
  real workflow in Docker via [`act`](https://github.com/nektos/act) for each
  fixture scenario and asserts on the **exact** aggregated numbers. Its output is
  saved to `act-result.txt`. It is gated so a normal `bun test` stays fast and
  the in-container test step can never recurse into `act`.

## CI workflow

`.github/workflows/test-results-aggregator.yml` runs on push / pull_request /
manual dispatch / a weekly schedule. It checks out the repo, installs Bun, runs
the unit tests, runs the aggregator over the fixtures (writing the job summary),
and a dependent `report` job consumes the upstream job outputs. It is
least-privilege (`contents: read`) and passes `actionlint`.
