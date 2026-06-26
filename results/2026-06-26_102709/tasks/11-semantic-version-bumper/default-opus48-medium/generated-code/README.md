# Semantic Version Bumper

Reads a semantic version (`VERSION` file or `package.json`), inspects a
[Conventional Commits](https://www.conventionalcommits.org/) log, computes the
next version, updates the version file, prepends a grouped changelog entry, and
prints the new version.

## Bump rules

| Commit                                   | Bump  |
|------------------------------------------|-------|
| `feat: ...`                              | minor |
| `fix: ...`                               | patch |
| `feat!: ...` / `BREAKING CHANGE:` footer | major |
| anything else (docs, chore, ...)         | none  |

The highest-precedence bump across all commits wins (major > minor > patch).

## Usage

```bash
python3 bump_version.py \
  --version-file VERSION \
  --commits commits.log \
  --changelog CHANGELOG.md \
  --date 2026-06-26
```

`commits.log` is a NUL-delimited list of commit messages, exactly what
`git log -z --format=%B` produces. When `GITHUB_OUTPUT` is set the script also
emits `new_version`/`bumped` step outputs.

## Testing (red/green TDD)

The module was built test-first: each function in `bump_version.py` was added
only after a failing test in `tests/` demanded it.

```bash
python3 -m pytest tests/ -v
```

- `tests/test_version.py`, `test_bump.py`, `test_changelog.py`, `test_cli.py`
  — fast unit/CLI coverage.
- `tests/fixtures/*.log` — mock commit logs for each scenario.
- `tests/test_workflow_structure.py` — YAML structure, action references,
  `actionlint` validation.
- `tests/test_act_workflow.py` — runs the real GitHub Actions workflow through
  [`act`](https://github.com/nektos/act) for the minor/major/no-release cases,
  asserting exact expected versions. Output is captured to `act-result.txt`.

## CI

`.github/workflows/semantic-version-bumper.yml` checks out the repo, sets up
Python, and runs the bumper, exposing the computed version as a job output.
