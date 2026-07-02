# Semantic Version Bumper (TypeScript + Bun)

Parses a version file (plain `VERSION` or `package.json`), determines the next
semantic version from conventional commit messages, updates the version file,
prepends a changelog entry, and prints the new version.

Bump rules (strongest wins):

| Signal | Bump |
| --- | --- |
| `!` marker (`feat!:`) or `BREAKING CHANGE:` / `BREAKING-CHANGE:` footer | major |
| `feat:` | minor |
| `fix:` | patch |
| anything else (`docs:`, `chore:`, non-conventional, ...) | none (no-op) |

## Usage

```bash
bun run src/cli.ts \
  --version-file VERSION \            # or a package.json
  --commits-file fixtures/commits-feat.log \
  --changelog-file CHANGELOG.md \     # optional, default CHANGELOG.md
  --date 2026-07-02                   # optional, default today (UTC)
```

Output contract (greppable by CI):

```
OLD_VERSION=1.1.0
BUMP=minor
NEW_VERSION=1.2.0
1.2.0
```

Commit-log files contain full commit messages (subject + body) separated by a
`====COMMIT====` line — the shape `git log --format=%B%n====COMMIT====`
produces. Mock logs live in `fixtures/`.

## Layout

- `src/semver.ts` — parse/format/bump `SemVer` triples
- `src/commits.ts` — conventional-commit parsing + bump determination
- `src/changelog.ts` — changelog entry rendering/prepending
- `src/versionFile.ts` — `VERSION` / `package.json` read+write
- `src/commitLog.ts` — `====COMMIT====`-delimited log parsing
- `src/bumper.ts` — end-to-end orchestration
- `src/cli.ts` — CLI entry point
- `tests/` — one test file per module, built red/green TDD (each test file
  header notes its RED cycle); `tests/workflow.test.ts` validates the CI
  workflow structure and asserts `actionlint` exits 0
- `fixtures/` — mock commit logs (feat / fix / breaking / none)
- `scripts/run-act-tests.ts` — act-based end-to-end harness

## Testing

```bash
bun test                          # 54 unit + workflow-structure tests
bun run scripts/run-act-tests.ts  # full pipeline via act (writes act-result.txt)
```

The act harness builds a throwaway git repo per case (project files + that
case's start `VERSION` + its fixture copied to `commits.log`), runs
`act push --rm`, appends all output to `act-result.txt`, and asserts exact
expected versions (e.g. feat on 1.1.0 must produce exactly `NEW_VERSION=1.2.0`)
plus a "Job succeeded" line for both workflow jobs.

## CI

`.github/workflows/semantic-version-bumper.yml` runs on push / pull_request /
workflow_dispatch: job `test` (install Bun + actionlint, `bun test`) then job
`bump` (needs `test`; runs the CLI against `commits.log` if present, else the
default fixture, and echoes the results).
