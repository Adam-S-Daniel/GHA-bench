# Semantic Version Bumper

Reads a semantic version from a `VERSION` file or `package.json`, inspects a set
of [conventional commit](https://www.conventionalcommits.org/) messages,
computes the next version, updates the version file, and prepends a grouped
changelog entry.

| Commit type            | Bump  |
| ---------------------- | ----- |
| breaking (`feat!:` / `BREAKING CHANGE:` footer) | major |
| `feat:`                | minor |
| `fix:`                 | patch |
| anything else          | none  |

The highest-precedence commit in the batch wins. No git dependency: commits are
supplied as data (a `commits.txt` fixture, one record per line), which keeps the
tool trivially testable and lets CI feed in fixture data.

## Usage

```bash
python3 version_bumper.py \
  --version-file VERSION \      # or package.json
  --commits-file commits.txt \
  --changelog-file CHANGELOG.md \
  --date 2026-06-26            # optional; defaults to today (UTC)
```

It prints machine-readable lines (`OLD_VERSION=`, `BUMP=`, `NEW_VERSION=`) plus
a human summary, and exits non-zero with a clear message on bad input.

## Development (red/green TDD)

The code was built test-first. `tests/test_version_bumper.py` holds the unit
tests (each written before its implementation); `tests/test_workflow_structure.py`
validates the workflow's shape and that `actionlint` passes;
`tests/test_act_workflow.py` runs **every** scenario end-to-end through the
GitHub Actions workflow with `act`.

```bash
python3 -m pytest tests/ -v        # everything (needs act + docker for the e2e file)
python3 -m pytest tests/test_version_bumper.py -v   # fast unit tests only
```

## CI

`.github/workflows/semantic-version-bumper.yml` checks out the repo, sets up
Python, detects the version source, runs the bumper, and reports the next
version. It triggers on push, pull_request, a weekly schedule, and manual
dispatch, and runs with least-privilege (`contents: read`).

## Fixtures

`fixtures/<case>/` directories are the mock commit logs / version files. Each is
a known input with a hand-computed expected output asserted by the act harness;
the captured `act` output for every case is written to `act-result.txt`.
