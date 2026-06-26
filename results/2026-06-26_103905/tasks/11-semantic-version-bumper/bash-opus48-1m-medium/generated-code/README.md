# Semantic Version Bumper (Bash)

Parses a current semantic version (from a plain `VERSION` file or a
`package.json`), determines the next version from Conventional Commit messages,
updates the version source in place, generates a grouped changelog entry, and
prints the new version.

Bump rules (highest precedence wins):

| Commit signal                                   | Bump  |
|-------------------------------------------------|-------|
| `type!:` or a `BREAKING CHANGE:` footer         | major |
| `feat:`                                         | minor |
| `fix:`                                          | patch |
| anything else (`chore`, `docs`, ...)            | none  |

## Usage

```bash
./bump-version.sh --version-file VERSION --commits commits.txt [--changelog CHANGELOG.md]
./bump-version.sh --package-json package.json --commits commits.txt
```

The new version is written to stdout (last line); a human-readable summary and
all errors go to stderr. Exit codes: `0` success, `1` usage/input error,
`2` no conventional commits (nothing to bump).

## Files

- `bump-version.sh` — the implementation (`#!/usr/bin/env bash`, passes
  `shellcheck` and `bash -n`).
- `tests/bump-version.bats` — unit tests for the script logic (TDD red/green).
- `tests/workflow-structure.bats` — static checks of the workflow (structure,
  script references, actionlint).
- `tests/act-harness.bats` — end-to-end tests that run every case **through**
  the GitHub Actions workflow via `act`, asserting exact versions and job
  success. Output is recorded to `act-result.txt`.
- `fixtures/` — mock commit logs and version sources used as test fixtures.
- `.github/workflows/semantic-version-bumper.yml` — CI pipeline that runs the
  bumper (triggers: push, pull_request, schedule, workflow_dispatch).

## Running the tests

```bash
# Fast logic + workflow-structure tests (no Docker):
bats tests/bump-version.bats tests/workflow-structure.bats

# Full pipeline tests through act (requires Docker; one `act push` per case):
bats tests/act-harness.bats
```
