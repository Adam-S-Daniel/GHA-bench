# Semantic Version Bumper

A small TypeScript/Bun tool that reads a semantic version, inspects a log of
[Conventional Commits](https://www.conventionalcommits.org), computes the next
version, updates the version file, and generates a changelog entry.

```
feat     -> minor bump      (1.4.2 -> 1.5.0)
fix      -> patch bump      (1.4.2 -> 1.4.3)
breaking -> major bump      (1.4.2 -> 2.0.0)   ("!" marker or "BREAKING CHANGE:" footer)
other    -> no bump         (docs, chore, style, refactor, test, ...)
```

The overall bump is the highest-precedence bump found across all commits.

## Usage

```bash
bun run src/index.ts \
  --version-file version.txt \        # or a package.json
  --commits fixtures/commits.txt \    # a delimited commit log (see fixtures/)
  --changelog CHANGELOG.md \
  --date 2026-06-27                   # optional; defaults to today (UTC)

# Flags: -f/--version-file, -c/--commits, --changelog, --date,
#        --delimiter, --dry-run, -h/--help
```

The CLI prints machine-readable lines that CI can grep:

```
PREVIOUS_VERSION=1.1.0
NEW_VERSION=1.2.0
BUMP_TYPE=minor
CHANGED=true
```

and, when `$GITHUB_OUTPUT` is set, also emits `new-version`, `bump-type`,
`previous-version`, and `changed` as GitHub Actions step outputs.

## Version sources

- **`*.json`** (e.g. `package.json`): only the `version` field is read and
  rewritten; all other keys and their order are preserved.
- **anything else** (e.g. `version.txt`): the file holds just the version
  string. A leading `v` is tolerated and restored on write.

## Commit-log fixtures

Commits are stored in a fixture file, one block per commit, separated by a
line containing `--COMMIT--` (override with `--delimiter`). A block's first
line is the header; remaining lines are the body (where a `BREAKING CHANGE:`
footer may live). See `fixtures/` for examples covering each bump type.

## Project layout

| Path                 | Responsibility                                        |
| -------------------- | ----------------------------------------------------- |
| `src/semver.ts`      | parse / format / bump semantic versions               |
| `src/commits.ts`     | parse conventional commits → per-commit + total bumps |
| `src/changelog.ts`   | render a Keep-a-Changelog entry, prepend to the file  |
| `src/version-file.ts`| read/write package.json or plain version files        |
| `src/bumper.ts`      | orchestrate the full pipeline                         |
| `src/index.ts`       | thin, testable CLI                                     |

## Testing

Built with strict red/green TDD — every module has a failing test written
before its implementation.

```bash
bun run test:unit   # fast unit tests (no Docker)
bun test            # unit tests + the act integration harness (needs Docker)
```

`tests/workflow.test.ts` is the GitHub Actions integration harness. For each
case it builds an isolated git repo with the project + fixture data, runs the
workflow through [`act`](https://github.com/nektos/act) in a Docker container,
archives the output to `act-result.txt`, and asserts the **exact** resulting
version, bump type, and changelog content.

## CI

`.github/workflows/semantic-version-bumper.yml` runs on push / pull_request /
manual dispatch / a weekly schedule: it checks out the repo, installs Bun,
runs the unit tests, and bumps the version. It passes `actionlint` and runs
successfully under `act`.
