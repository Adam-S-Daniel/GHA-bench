# PR Label Assigner

Given a list of changed file paths (a mock PR file list), apply labels using
configurable **glob → label** rules. Supports glob patterns, multiple labels
per file, and **priority ordering when rules conflict**. Outputs the final
label set. Pure Python standard library — no third-party dependencies.

## Files

| Path | Purpose |
|------|---------|
| `pr_label_assigner.py` | The script: glob engine, rule evaluation, CLI. |
| `label-rules.json` | Configurable rules (`pattern`, `labels`, `priority?`, `group?`). |
| `changed_files.txt` | Mock PR changed-files list (default = case1). |
| `fixtures/caseN/` | Per-case `changed_files.txt` + `expected.json`. |
| `.github/workflows/pr-label-assigner.yml` | CI workflow that runs the script. |
| `tests/` | pytest unit + workflow-structure + act-artifact tests. |
| `run_act_tests.py` | Runs every fixture through the workflow via `act`. |
| `act-result.txt` | Recorded output of the act pipeline runs. |

## Rule semantics

A rule maps a glob pattern to one or more labels, with an optional `priority`
(default 0) and an optional `group`:

```json
{"pattern": "src/api/**", "labels": ["api", "backend"], "priority": 40, "group": "area"}
```

* **Glob matching** is minimatch-style: `*` stays within a path segment, `**`
  crosses directories, `?` matches one char. A pattern with no `/` matches the
  file's *basename* (so `*.test.*` labels test files at any depth).
* **Multiple labels per file**: every matching rule contributes its labels;
  the final set is their de-duplicated union across all changed files.
* **Priority ordering**: output labels are sorted by effective priority
  (highest first), ties broken alphabetically.
* **Conflict resolution**: for a single file, if two matching rules share a
  `group`, only the higher-priority rule applies (e.g. `docs/internal/**` →
  `internal-docs` wins over `docs/**` → `documentation`).

## Usage

```bash
python3 pr_label_assigner.py --config label-rules.json --files-from changed_files.txt
python3 pr_label_assigner.py --config label-rules.json docs/a.md src/api/b.py   # positional
python3 pr_label_assigner.py --config label-rules.json --files-from changed_files.txt --format json
```

The script prints a `RESULT_LABELS=<comma,separated>` line (and `RESULT_COUNT=`)
for easy CI assertions, and writes `labels=` / `count=` to `$GITHUB_OUTPUT`
when run inside GitHub Actions.

## Testing

Developed with red/green TDD. Two layers:

```bash
# 1. Fast unit + workflow-structure tests
python3 -m pytest tests/ -v

# 2. Full pipeline: every fixture executed by the real workflow via act
python3 run_act_tests.py        # writes act-result.txt, asserts exact labels
```

`run_act_tests.py` builds a throwaway git repo per fixture, runs `act push`,
appends delimited output to `act-result.txt`, and asserts each case produced
the exact expected labels with every job reporting `Job succeeded`.
