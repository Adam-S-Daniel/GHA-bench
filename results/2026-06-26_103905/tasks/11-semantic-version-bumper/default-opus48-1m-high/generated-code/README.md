# Semantic Version Bumper

Parses a version file (plain `VERSION` **or** `package.json`), reads a
conventional-commit log, decides the next [SemVer](https://semver.org) version
(`feat` → minor, `fix` → patch, breaking → major), updates the version file,
prepends a changelog entry, and prints the new version.

## Layout

| Path | Purpose |
| --- | --- |
| `src/bumper.js` | Core library: parse commits, decide bump, bump version, read/write version file, generate changelog, end-to-end `bump()`. Pure where possible. |
| `src/cli.js` | CLI wrapper. Auto-detects the version file, writes outputs to stdout and `$GITHUB_OUTPUT`. |
| `test/bumper.test.js` | Unit tests (built test-first, red→green) for every function. |
| `test/workflow.test.js` | Workflow **structure** tests + actionlint check. |
| `fixtures/*.commits.log` | Mock commit logs (commits separated by `--==COMMIT==--`). |
| `.github/workflows/semantic-version-bumper.yml` | CI/CD pipeline that runs the script. |
| `run-act-tests.sh` | Integration harness: runs every case through the workflow via `act`. |

## Usage

```bash
# Version comes from VERSION or package.json (auto-detected).
node src/cli.js --commits commits.log --changelog CHANGELOG.md
# -> OLD_VERSION=1.1.0 / BUMP_TYPE=minor / NEW_VERSION=1.2.0
```

## Testing

```bash
node --test            # 38 unit + structure tests
actionlint .github/workflows/semantic-version-bumper.yml
./run-act-tests.sh     # runs all 3 cases through the pipeline with `act`
```

`run-act-tests.sh` builds an isolated git repo per case, runs `act push --rm`,
appends each run's output to `act-result.txt`, and asserts the **exact** new
version / bump type, a zero exit code, and `Job succeeded` for every case.

Development followed red/green TDD: each function got a failing test first, then
the minimum code to pass it (see the commit-style comments in the test file).
