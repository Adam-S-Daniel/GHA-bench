# PR Label Assigner

Assigns labels to a PR from its changed file paths using configurable
glob rules. Built with red/green TDD in pure-stdlib Python 3.

## How it works

- **Config** (`fixtures/rules.json`): `{"rules": [{"pattern", "labels", "priority"?}]}`.
- **Glob semantics**: `**` crosses path segments, `*`/`?` stay within one
  segment, and a pattern with no `/` matches the basename at any depth
  (so `*.test.*` hits `src/deep/app.test.js`).
- **Multiple labels**: each rule can emit several labels; a file matching
  several rules gets the union.
- **Priority conflicts**: per file, only the matching rules with the
  highest `priority` (default 0) contribute — e.g. `src/generated/**`
  at priority 5 suppresses the generic `src/** -> source` label for
  generated files, without affecting other files.
- **Changed files** are mocked via a text fixture (one path per line),
  standing in for `git diff --name-only` / the PR files API.

Run: `python3 labeler.py --config fixtures/rules.json --files fixtures/changed_files.txt`
→ prints `LABELS: a,b,c` (or `LABELS: (none)`); config errors exit 2 with
a message naming the offending rule.

## Tests

- `tests/test_labeler.py` — TDD unit suite (matching, label union,
  priority, config validation, CLI).
- `tests/test_workflow.py` — workflow structure tests: YAML shape,
  triggers, job dependency, referenced paths exist, actionlint exit 0.
- `act_harness.py` — end-to-end: builds a temp git repo per test case
  (project + case fixtures), runs the workflow via `act push --rm`,
  writes `act-result.txt`, and asserts exact expected label sets and
  that every job succeeded. Run with `python3 act_harness.py`.

## CI

`.github/workflows/pr-label-assigner.yml`: on push / pull_request /
workflow_dispatch, job `test` runs the unit suite, then job `label`
(needs: test) computes the label set, exports it via `GITHUB_OUTPUT`,
and reports the final set.
