# Test Results Aggregator

A pure-Bash tool that parses test result files from a matrix build (JUnit XML
and JSON), aggregates them, detects **flaky** tests, and renders a Markdown
summary suitable for a GitHub Actions job summary.

## What it does

Given one or more result files (each file is one matrix leg, e.g. one
OS/version combination), `aggregate-test-results.sh`:

- parses **JUnit XML** (`<testsuites>`/`<testsuite>` with `<testcase>` elements)
  and a simple **JSON** schema;
- computes totals: **passed / failed / skipped / total** and summed
  **duration** (seconds);
- identifies **flaky tests** — a test (identified by `classname.name`) that
  **passed in at least one run and failed in at least one other run**;
- emits GitHub-flavoured **Markdown** and, optionally, a machine-readable
  `key=value` counts file.

## Usage

```bash
# Aggregate every *.xml / *.json file in a directory:
./aggregate-test-results.sh fixtures/

# Or pass individual files, write Markdown to a file, and emit a counts file:
./aggregate-test-results.sh \
    --output summary.md \
    --counts-file counts.env \
    run-ubuntu.xml run-macos.xml run-windows.json
```

Options: `-o/--output <file>`, `-c/--counts-file <file>`, `-t/--title <title>`,
`-h/--help`. Exit codes: `0` ok, `1` runtime error, `2` usage error, `3`
missing `jq` (needed only for JSON input).

## Input formats

**JUnit XML** — a `<testcase>` is *failed* if it has a `<failure>`/`<error>`
child, *skipped* if it has a `<skipped>` child, otherwise *passed*. Both
`<testsuites>` and bare `<testsuite>` roots are supported.

**JSON** — either an object `{ "tests": [ ... ] }` (or `"testcases"`) or a bare
array `[ ... ]`. Each element:

```json
{ "classname": "core.MathTest", "name": "test_add", "status": "passed", "duration": 0.10 }
```

`status` is normalised tolerantly: `pass*`/`ok`/`success` → passed,
`fail*`/`err*` → failed, `skip*`/`pending`/`ignore` → skipped. `classname`
(or `suite`) and `duration` (or `time`) are optional.

## Output

```markdown
# Test Results Summary

| Result | Count |
| :--- | ---: |
| Passed | 11 |
| Failed | 5 |
| Skipped | 2 |
| **Total** | **18** |
| Duration | 2.85s |

## Flaky Tests

2 test(s) passed in some runs and failed in others:

| Test | Passed | Failed |
| :--- | ---: | ---: |
| `core.MathTest.test_divide` | 2 | 1 |
| `core.NetTest.test_timeout` | 2 | 1 |
```

The optional counts file holds `passed=`, `failed=`, `skipped=`, `unknown=`,
`total=`, `flaky=`, `duration=`.

## CI integration

`.github/workflows/test-results-aggregator.yml` runs on push / pull_request /
schedule / workflow_dispatch. The `aggregate` job runs the script over
`fixtures/`, appends the Markdown to `$GITHUB_STEP_SUMMARY`, and exposes the
totals as job outputs; a dependent `gate` job consumes those outputs and fails
the build if zero tests were aggregated.

## Tests

Tests use [bats-core](https://github.com/bats-core/bats-core) and all
behavioural testing runs through the workflow via [`act`](https://github.com/nektos/act):

```bash
bats tests/structure.bats   # fast: workflow/script/fixture shape + actionlint
bats tests/act.bats         # runs the workflow in Docker via act per scenario
```

`tests/act.bats` builds a throwaway git repo per scenario
(`tests/scenarios/<name>/`), runs `act push --rm`, appends the full transcript
to `act-result.txt`, and asserts on the exact expected totals for that
scenario's known input.
