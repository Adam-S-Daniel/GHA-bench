# PR Label Assigner

Assigns labels to a PR based on its changed file paths, driven by
configurable glob rules. Built with red/green TDD (Python `unittest`).

## Rule format (`rules.json`)

```json
[
  {"pattern": "docs/**", "labels": ["documentation"], "priority": 1},
  {"pattern": "docs/generated/**", "labels": ["generated"], "priority": 10, "exclusive": true},
  {"pattern": "src/api/**", "labels": ["api", "backend"]},
  {"pattern": "*.test.*", "labels": ["tests"]}
]
```

- `pattern` — glob: `**` crosses `/`, `*`/`?` stay within one segment; a
  pattern without `/` matches the basename at any depth.
- `labels` — one or more labels added when the pattern matches.
- `priority` (default 0) — per file, matching rules apply highest first.
- `exclusive` — when this is the highest-priority match for a file,
  lower-priority rules are skipped for that file (conflict resolution).

Labels from all changed files are unioned and printed sorted:
`FINAL_LABELS: api,documentation,tests` (or `FINAL_LABELS: (none)`).

## Usage

```sh
python3 labeler.py --rules rules.json --files changed_files.txt
```

`changed_files.txt` mocks the PR's changed-file list, one path per line.
Bad input (missing files, invalid JSON, malformed rules) exits 2 with a
clear `ERROR:` message.

## Tests

- `python3 -m unittest test_labeler` — core TDD suite (22 tests).
- `python3 -m unittest test_workflow_structure` — workflow YAML structure,
  referenced-file existence, actionlint exit code.
- `./run_act_tests.sh` — runs every fixture case in `fixtures/case*/`
  through the GitHub Actions workflow
  (`.github/workflows/pr-label-assigner.yml`) via `act push --rm`,
  appends all output to `act-result.txt`, and asserts exact expected
  label sets plus `Job succeeded` per case.
