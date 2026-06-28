# Semantic Version Bumper

A small TypeScript/Bun tool that reads a semantic version (from a plain version
file or a `package.json`), inspects [Conventional Commits](https://www.conventionalcommits.org/)
to decide the next version, updates the version file, generates a changelog
entry, and prints the new version.

| Strongest commit signal | Bump  | Example          |
| ----------------------- | ----- | ---------------- |
| breaking change         | major | `1.4.2 -> 2.0.0` |
| `feat`                  | minor | `1.4.2 -> 1.5.0` |
| `fix`                   | patch | `1.4.2 -> 1.4.3` |
| anything else           | none  | unchanged        |

A change is "breaking" when its subject carries the `!` marker (`feat!:`,
`fix(api)!:`) **or** its body contains a `BREAKING CHANGE:` / `BREAKING-CHANGE:`
footer. Breaking wins over `feat`, which wins over `fix`.

## Usage

```bash
bun run version-bumper.ts \
  --version-file version.txt \   # or package.json (.json => JSON-aware)
  --commits commits.log \        # fixture log; omit to read real `git log`
  --changelog CHANGELOG.md       # add --no-changelog to skip
```

Useful flags: `--git-range v1.0.0..HEAD` (when reading from git),
`--date 2026-06-28` (deterministic changelog stamp), `--dry-run` (compute but
write nothing), `--help`.

The tool prints a human summary plus stable machine lines and, under GitHub
Actions, publishes step outputs to `$GITHUB_OUTPUT`:

```
NEW_VERSION=1.2.0
BUMP_TYPE=minor
VERSION_CHANGED=true
```

### Commit log format

Commits in a log file are separated either by a `--- COMMIT ---` line (readable,
used by the fixtures) or by the ASCII record separator `\x1e` that
`git log --format=%B%x1e` emits. A log with no separator is treated as a single
commit, so multi-commit logs must place a delimiter between entries.

## Development — red/green TDD

Every function was built test-first (`version-bumper.test.ts`). Run the fast
unit + structure tests:

```bash
bun test version-bumper.test.ts workflow-structure.test.ts
```

## CI pipeline (`act`)

`.github/workflows/semantic-version-bumper.yml` checks out the repo, installs
Bun, runs the unit tests, then runs the bumper against the committed
`version.txt` + `commits.log`. The end-to-end harness (`act-harness.test.ts`)
runs **every** functional case through the workflow with [`act`](https://github.com/nektos/act):

```bash
bun test act-harness.test.ts        # all cases; writes act-result.txt
ACT_CASES=feat bun test act-harness.test.ts   # a single case
```

Each case spins up an isolated git repo, runs `act push --rm`, appends the full
output to `act-result.txt`, and asserts the **exact** next version and that the
job succeeded.

## Files

| File                                          | Purpose                              |
| --------------------------------------------- | ------------------------------------ |
| `version-bumper.ts`                           | The tool (pure logic + CLI).         |
| `version-bumper.test.ts`                      | TDD unit tests.                      |
| `workflow-structure.test.ts`                  | Workflow YAML / structure tests.     |
| `act-harness.test.ts`                         | End-to-end pipeline tests via `act`. |
| `fixtures/{feat,fix,breaking}/`               | Mock version files + commit logs.    |
| `.github/workflows/semantic-version-bumper.yml` | The CI/CD workflow.                |
