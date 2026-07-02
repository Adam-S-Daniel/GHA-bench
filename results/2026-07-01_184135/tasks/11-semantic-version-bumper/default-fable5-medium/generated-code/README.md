# Semantic Version Bumper

Zero-dependency Node.js tool that reads a semantic version from a plain
`VERSION` file or a `package.json`, classifies conventional commit messages
(breaking → major, `feat` → minor, `fix` → patch), writes the bumped version
back, prepends a grouped `CHANGELOG.md` entry, and prints the new version as
`NEW_VERSION=x.y.z`.

## Layout

- `src/bumper.js` — library + CLI (`--version-file`, `--commits-file`, `--changelog-file`, `--date`)
- `test/bumper.test.js` — 24 unit tests (built-in `node:test`), written red/green TDD; the TDD cycle log is in the file header
- `fixtures/` — mock commit logs (feat / fix / breaking) and a fixture `package.json`
- `.github/workflows/semantic-version-bumper.yml` — CI pipeline: `test` job (unit suite) → `bump` job (end-to-end run against a fixture)
- `scripts/run-act-tests.sh` — end-to-end harness: 3 test cases, each in a fresh temp git repo, executed via `act push --rm --pull=false`; output captured to `act-result.txt` with exact-value assertions
- `scripts/test_workflow_structure.py` — workflow YAML structure tests + actionlint gate

## Commit-log fixture format

One commit per line; multi-line bodies encode newlines as literal `\n`
(so a line can carry a `BREAKING CHANGE:` footer). This keeps the core
logic pure and testable without a real git history.

## Running

```sh
node --test test/                      # unit tests (host)
python3 scripts/test_workflow_structure.py   # workflow structure tests
bash scripts/run-act-tests.sh          # full pipeline via act (needs Docker)
node src/bumper.js --version-file VERSION --commits-file fixtures/feat-commits.txt
```

The CI workflow selects its test case from an optional `test-case.env`
file in the repo root (`VERSION_FILE=...`, `COMMITS_FILE=...`); without
it, defaults run against `VERSION` + `fixtures/feat-commits.txt`.
