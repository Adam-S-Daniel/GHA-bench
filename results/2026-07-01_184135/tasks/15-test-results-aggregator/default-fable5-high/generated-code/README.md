# Test Results Aggregator

Aggregates test result files from a matrix build (JUnit XML + JSON), computes
totals (passed / failed / skipped / duration), flags **flaky tests** (passed in
some runs, failed in others), and emits a markdown summary suitable for
`$GITHUB_STEP_SUMMARY`.

Pure Python standard library — no pip installs needed anywhere, including
inside the CI container.

## Layout

| Path | Purpose |
| --- | --- |
| `aggregator.py` | Parsers (JUnit XML, JSON), aggregation, flaky detection, markdown rendering, CLI |
| `tests/test_aggregator.py` | Unit tests (stdlib `unittest`), one class per TDD cycle |
| `tests/test_workflow_structure.py` | Workflow structure tests: YAML shape, referenced paths, actionlint |
| `fixtures/` | Sample result files: `case1-matrix-flaky` (mixed + 2 flaky tests), `case2-all-green`, `malformed` |
| `.github/workflows/test-results-aggregator.yml` | CI workflow: `unit-tests` job → `aggregate` job |
| `harness.py` | Runs every test case through the workflow via `act push --rm`, writes `act-result.txt` |

## Usage

```bash
python3 aggregator.py <results-dir> --output summary.md
```

stdout carries machine-readable lines for CI assertions
(`RESULT total=12 passed=7 failed=3 skipped=2 duration=11.10 flaky=2`,
`FLAKY <test-id>`); the markdown summary goes to `--output`.

## Tests

```bash
python3 -m unittest discover -s tests -t . -v   # unit + structure tests
python3 harness.py                              # end-to-end via act (writes act-result.txt)
```

## Approach (red/green TDD)

Each feature was built as a strict red/green cycle — failing test first, then
the minimum implementation, then refactor:

1. JUnit XML parsing (`<testsuites>`/`<testsuite>` roots; `<failure>`/`<error>`
   → failed, `<skipped>` → skipped)
2. JSON parsing (schema documented in `aggregator.py`; unknown statuses rejected)
3. Aggregation across runs + flaky detection (flaky = passed somewhere AND
   failed somewhere; consistent failures are *not* flaky)
4. Markdown rendering (totals table, flaky table with pass/fail locations,
   per-run breakdown)
5. CLI (exit 0 with stable `RESULT`/`FLAKY` stdout lines; input errors →
   `ERROR: ...` on stderr, exit 1)
6. Workflow structure tests were written before the workflow file existed.

## CI / act

The workflow's `aggregate` job reads `test-results/` if present (the harness
drops each case's fixtures there), else falls back to the bundled sample
fixtures — so a plain push to GitHub also succeeds. `harness.py` builds a temp
git repo per case, runs `act push --rm`, asserts exit code 0, both jobs report
`Job succeeded`, and the output matches hand-computed exact values.
