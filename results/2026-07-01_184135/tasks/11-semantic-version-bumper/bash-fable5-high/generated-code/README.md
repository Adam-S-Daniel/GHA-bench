# Semantic Version Bumper

A bash implementation of a conventional-commit-driven semantic version bumper,
built with red/green TDD (bats-core) and validated end-to-end through GitHub
Actions via `act`.

## What it does

`bump_version.sh` reads the current version from a plain `VERSION` file or a
`package.json`, scans a commit log for conventional commit messages, and:

| Commits contain                                  | Bump  | Example       |
|--------------------------------------------------|-------|---------------|
| `type!:` prefix or `BREAKING CHANGE` footer      | major | 1.1.0 → 2.0.0 |
| `feat:` / `feat(scope):`                         | minor | 1.1.0 → 1.2.0 |
| `fix:` / `fix(scope):`                           | patch | 2.3.4 → 2.3.5 |
| only docs/chore/style/...                        | none  | unchanged     |

It rewrites the version file, prepends a grouped changelog entry
(Breaking Changes / Features / Fixes) to `CHANGELOG.md`, and prints the new
version as the last line of stdout. Inside GitHub Actions it also writes
`old_version` / `new_version` / `bump_type` to `$GITHUB_OUTPUT`.

```sh
./bump_version.sh --version-file VERSION --commits commits.txt \
                  --changelog CHANGELOG.md --date 2026-07-02
```

Without `--commits` it falls back to `git log` since the last tag.

## Layout

- `bump_version.sh` — the script; sourceable for unit tests via `BUMP_VERSION_LIB=1`.
- `tests/bump_version.bats` — 27 unit/CLI tests, written test-first in 7 TDD cycles.
- `tests/workflow.bats` — workflow structure tests (actionlint, YAML shape, path refs).
- `tests/fixtures/` — mock commit logs and a fixture `package.json`.
- `ci-fixture/` — the test case the CI workflow executes (swapped per case by the harness).
- `.github/workflows/semantic-version-bumper.yml` — CI: `unit-tests` (bats) → `bump-version` (runs the script on the fixture and asserts the expected version).
- `run_act_tests.sh` — end-to-end harness: builds a temp git repo per test case, runs `act push --rm`, appends output to `act-result.txt`, and asserts exact versions, bump types, changelog bullets, and job success.

## Running

```sh
bats tests            # local unit + workflow-structure tests
./run_act_tests.sh    # full pipeline: 3 scenarios through act (writes act-result.txt)
```
