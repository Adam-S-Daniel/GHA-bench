# PR Label Assigner

Given a PR's changed file paths, apply labels from configurable path-to-label
glob rules. Supports globstar patterns, multiple labels per file, and
priority-based conflict resolution.

## Files

| File | Purpose |
|------|---------|
| `label_assigner.py` | The engine + CLI. Pure, dependency-free Python. |
| `rules.json` | Default path-to-label rules (config). |
| `tests/test_label_assigner.py` | Unit tests (written red-first, TDD). |
| `tests/test_workflow_structure.py` | YAML structure + actionlint checks. |
| `fixtures/` | Mock changed-file lists (+ optional per-case `rules.json`). |
| `.github/workflows/pr-label-assigner.yml` | The CI workflow. |
| `run_act_tests.py` | Runs every case end-to-end through `act`. |
| `act-result.txt` | Captured `act` output (generated artifact). |

## How it works

1. **Glob matching** (`glob_match`) — a hand-written globstar translator so
   `*` stays within a path segment while `**` spans `/` boundaries (stdlib
   `fnmatch` cannot distinguish the two).
2. **Engine** (`assign_labels`) — union of all matched labels (multiple labels
   per file). Rules may carry a `priority` (orders output, higher first) and a
   `group` (mutually exclusive — highest priority wins the conflict).
3. **Config** (`load_rules` / `load_changed_files`) — every failure becomes a
   clear `ConfigError` instead of a traceback.

## Rule format (`rules.json`)

```json
{ "rules": [
  { "pattern": "docs/**",      "label": "documentation", "priority": 10 },
  { "pattern": "src/api/**",   "label": "api",           "priority": 20 },
  { "pattern": "**/*.test.*",  "label": "tests",         "priority": 30 },
  { "pattern": "**/*",  "label": "size/large", "group": "size", "priority": 5 }
] }
```

## Run

```bash
# Unit + structure tests (TDD suite)
python3 -m pytest tests/ -v

# CLI directly
python3 label_assigner.py --config rules.json --files changed_files.txt

# Full end-to-end validation through GitHub Actions via act
python3 run_act_tests.py
```

The CLI emits a deterministic, machine-parseable contract line:

```
LABELS: tests,api,documentation,python
LABELS: (none)
```
