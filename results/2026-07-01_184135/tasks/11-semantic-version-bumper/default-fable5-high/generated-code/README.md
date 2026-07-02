# Semantic Version Bumper

A zero-dependency Node.js tool that reads the current semantic version from a
version file (`package.json` or plain `VERSION`), classifies conventional
commits (`breaking -> major`, `feat -> minor`, `fix -> patch`), rewrites the
version file, prepends a grouped changelog entry to `CHANGELOG.md`, and prints
the new version on stdout.

## Layout

| Path | Purpose |
| --- | --- |
| `src/semver-bump.js` | Library + CLI (`node src/semver-bump.js [--version-file f] [--commits-file f] [--changelog f]`) |
| `test/semver-bump.test.js` | 29 unit tests (built-in `node:test`), written red/green TDD cycle by cycle |
| `test/workflow_structure_test.py` | Workflow structure tests (YAML shape, path references, actionlint exit 0) |
| `fixtures/commits-*.log` | Mock commit logs (`<hash> <subject>` + body lines, `====` delimited — same shape as `git log --pretty=format:'%h %s%n%b%n===='`) |
| `.github/workflows/semantic-version-bumper.yml` | CI pipeline: `unit-tests` job, then `version-bump` job |
| `run-act-tests.sh` | E2E harness: 3 test cases, each a temp git repo run through the workflow via `act push --rm`, exact-value assertions, logs to `act-result.txt` |

## Behavior

- Version file auto-detection: explicit `--version-file`, else `package.json`,
  else `VERSION`; a clear error if none exists.
- Commits come from `--commits-file` (fixtures/CI) or fall back to
  `git log` since the last tag.
- The strongest bump across all commits wins; `!` after the type or a
  `BREAKING CHANGE:` footer means major. Commits like `chore:`/`docs:` alone
  produce no release: nothing is written and the current version is printed.
- Errors (missing/invalid version file, malformed commit log, bad JSON) exit 1
  with a meaningful message on stderr; stdout carries only the version.

## Running the tests

```sh
node --test test/semver-bump.test.js     # unit suite (also run inside CI)
python3 test/workflow_structure_test.py  # workflow structure checks
./run-act-tests.sh                       # full e2e through act (3 runs) -> act-result.txt
```

E2E cases asserted through the pipeline: `1.1.0 + feat -> 1.2.0`
(package.json), `2.3.4 + fix -> 2.3.5` (VERSION), `2.4.6 + breaking -> 3.0.0`
(VERSION), including exact changelog section/entry lines.
