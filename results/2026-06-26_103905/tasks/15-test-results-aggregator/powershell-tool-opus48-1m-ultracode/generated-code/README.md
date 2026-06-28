# Test Results Aggregator (PowerShell)

Parses test result files in **JUnit XML** and **JSON** formats, aggregates them
across a matrix of runs, computes totals, flags **flaky tests** (passed in some
runs, failed in others), and renders a markdown summary suitable for a GitHub
Actions job summary.

## Files

| File | Purpose |
| --- | --- |
| `TestResultsAggregator.psm1` | Module with all parsing/aggregation/rendering logic. |
| `Invoke-Aggregator.ps1` | CLI wrapper the workflow calls (writes markdown + machine-parseable stats). |
| `fixtures/` | Sample matrix: `junit-ubuntu.xml`, `junit-windows.xml`, `results-macos.json`. |
| `tests/TestResultsAggregator.Tests.ps1` | Pester unit tests (TDD) for the module. |
| `tests/Workflow.Tests.ps1` | Workflow structure tests, actionlint check, and the `act` harness. |
| `tests/cases/clean/` | A contrasting all-passing fixture set used by the act harness. |
| `.github/workflows/test-results-aggregator.yml` | CI workflow that runs the aggregator. |
| `act-result.txt` | Captured `act` output (one delimited block per test case). |

## Input formats

**JUnit XML** — a `<testsuites>` wrapper or a bare `<testsuite>` root, at any
depth. A `<testcase>` is `failed` if it has a `<failure>`/`<error>` child,
`skipped` for a `<skipped>` child, otherwise `passed`. The suite name is the
`classname` attribute, falling back to the enclosing `<testsuite name="...">`.

```xml
<testsuite name="Math" tests="2" failures="1" time="0.20">
  <testcase classname="Math" name="add" time="0.10"/>
  <testcase classname="Math" name="div" time="0.10"><failure message="boom"/></testcase>
</testsuite>
```

**JSON** — an object with a `tests` array (plus an optional document-level
`suite`/`name`), or a bare array of cases. Status synonyms (`pass`, `FAIL`,
`skip`, `error`, ...) are normalized case-insensitively; `duration` defaults to 0.

```json
{ "suite": "Math", "tests": [
  { "name": "add", "status": "passed", "duration": 0.11 },
  { "name": "div", "status": "failed", "duration": 0.12 }
] }
```

## Usage

```powershell
# Aggregate every .xml/.junit/.json file in a directory and print the summary.
./Invoke-Aggregator.ps1 -Path fixtures

# Also write the markdown to a file (e.g. to upload as an artifact).
./Invoke-Aggregator.ps1 -Path fixtures -OutputPath summary.md
```

When `$GITHUB_STEP_SUMMARY` is set (i.e. inside GitHub Actions), the markdown is
appended to it so it renders on the run's summary page. The CLI also prints a
machine-parseable line for CI assertions:

```
AGGREGATE_STATS TOTAL=18 PASSED=10 FAILED=5 SKIPPED=3 FLAKY=1 FILES=3 DURATION=1.31
FLAKY_TEST Math::div
```

## Flaky-test definition

A test is identified by `Suite::Name`. It is **flaky** when, across all
aggregated runs, it has at least one `passed` *and* at least one `failed`
result. A test that only ever fails (or only ever skips) is **not** flaky.

## Running the tests

```powershell
# Everything (unit tests + workflow structure + actionlint + act in Docker):
Invoke-Pester -Path tests

# Fast layers only (skip the Docker/act layer):
$cfg = New-PesterConfiguration
$cfg.Run.Path = 'tests'
$cfg.Filter.ExcludeTag = 'Act'
Invoke-Pester -Configuration $cfg
```

The `Act`-tagged tests stand up a throwaway git repo per case, run the workflow
with `act push --rm --pull=false`, append the output to `act-result.txt`, and
assert on the exact aggregate values each known-good fixture set must produce.
