# Test Results Aggregator (TypeScript + Bun)

Parses test result files in **JUnit XML** and **JSON** formats, aggregates them
across multiple files (simulating a matrix build), computes totals, detects
**flaky tests** (passed in some runs, failed in others), and renders a markdown
summary for a GitHub Actions job summary.

## Usage

```sh
bun run src/cli.ts --dir fixtures/matrix --out summary.md
```

Prints the markdown summary plus a machine-readable line
(`RESULT total=.. passed=.. failed=.. skipped=.. duration=.. flaky=..`),
writes `--out`, and appends to `$GITHUB_STEP_SUMMARY` when running in CI.

## Layout

| Path | Purpose |
| --- | --- |
| `src/types.ts` | Shared type contract (`TestFileResult`, `AggregateSummary`, …) |
| `src/junit.ts` | Dependency-free JUnit XML parser (`failure`/`error`/`skipped`, entity decoding) |
| `src/jsonResults.ts` | JSON results parser (single- and multi-suite shapes) with field validation |
| `src/aggregate.ts` | Totals + flaky detection keyed by `suite :: name` |
| `src/markdown.ts` | GitHub-flavored markdown summary renderer |
| `src/cli.ts` | Directory collector + CLI entry point |
| `fixtures/matrix` | 3-job matrix fixtures (ubuntu/macos JUnit XML + windows JSON) with 1 flaky test |
| `fixtures/all-pass` | All-passing fixture set |
| `.github/workflows/test-results-aggregator.yml` | CI pipeline (checkout → setup-bun → unit tests → aggregate) |

## Tests

Built with red/green TDD (one failing test per module first, then the minimal
implementation). Run everything with:

```sh
bun test
```

- `tests/{junit,jsonResults,aggregate,markdown,cli}.test.ts` — unit + CLI e2e tests
- `tests/workflow.test.ts` — workflow structure tests (YAML parse, path checks, actionlint exit 0)
- `tests/act.test.ts` — pipeline harness: each case builds a temp git repo with
  its fixture data as `results/`, runs `act push --rm`, appends output to
  `act-result.txt`, and asserts exit 0, `Job succeeded`, and exact aggregate
  values. It skips itself inside the act container (`ACT=true`) to avoid
  recursion — there, the workflow runs the unit suite instead.
