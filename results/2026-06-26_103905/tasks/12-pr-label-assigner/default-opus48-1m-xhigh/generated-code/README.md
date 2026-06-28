# PR Label Assigner

Given a list of changed file paths (a PR's changed files), apply labels from
configurable path-to-label glob rules. Supports glob patterns, multiple labels
per file, and priority ordering when rules conflict. Built **default mode →
Python 3** (stdlib only).

## Files

| File | Purpose |
|------|---------|
| `pr_label_assigner.py` | Core library + CLI: glob matcher, rule engine, label assignment. |
| `label-rules.json` | Configurable path-to-label rules (label, glob patterns, priority). |
| `fixtures/*.txt` | Mocked changed-file lists (the test fixtures). |
| `tests/test_pr_label_assigner.py` | TDD unit tests for the core logic. |
| `tests/test_workflow_structure.py` | Workflow YAML structure + path + actionlint checks. |
| `.github/workflows/pr-label-assigner.yml` | The CI/CD workflow. |
| `run_act_tests.py` | Runs every test case end-to-end through the workflow via `act`. |
| `act-result.txt` | Captured `act` output for all cases (required artifact). |

## Glob semantics

* `*` — any run of characters **except** `/`
* `?` — a single character except `/`
* `**` — across directory boundaries (zero or more path segments)
* a pattern with **no** `/` matches the **basename at any depth** (gitignore
  convention) — this is why `*.test.*` matches `src/foo.test.js`.

Multiple labels per file are supported (union across all files). When rules
conflict, the output is ordered by **descending priority**, ties broken
alphabetically, for deterministic results.

## Run it

```bash
# Unit + workflow-structure tests (fast, TDD loop)
python3 -m pytest tests/ -v

# CLI
python3 pr_label_assigner.py --config label-rules.json --files fixtures/case3_mixed.txt
# -> LABELS: api, tests, documentation, ci, source

# End-to-end through GitHub Actions in Docker (writes act-result.txt)
python3 run_act_tests.py
```

## Verified test cases (asserted exactly, through `act`)

| Case | Input fixture | Exact output |
|------|---------------|--------------|
| case1 | `case1_docs.txt` | `LABELS: documentation` |
| case2 | `case2_api.txt` | `LABELS: api, tests, source` |
| case3 | `case3_mixed.txt` | `LABELS: api, tests, documentation, ci, source` |

All 36 unit/structure tests pass, `actionlint` passes, and all three cases run
green through `act` (exit 0, exact labels, every job "Job succeeded").
