# Semantic Version Bumper (TypeScript + Bun)

Reads a version file (`package.json` or a plain `VERSION` file), inspects a
conventional-commit log, computes the next semantic version
(`feat → minor`, `fix → patch`, breaking `!`/`BREAKING CHANGE → major`),
writes the new version back, prepends a changelog entry, and prints the result.

## Layout

| Path | Purpose |
|------|---------|
| `src/semver.ts` | parse / format / bump `major.minor.patch` |
| `src/commits.ts` | parse conventional commits, resolve bump precedence |
| `src/changelog.ts` | render a grouped Markdown changelog entry |
| `src/bumper.ts` | file I/O orchestration (read version, write version + changelog) |
| `src/cli.ts` | CLI entry point used by the GitHub Actions workflow |
| `fixtures/` | mock commit logs used as test fixtures |
| `tests/` | `bun test` unit suite (red/green TDD) |
| `meta/workflow-structure.test.ts` | parses the workflow YAML + runs actionlint |
| `act-harness.ts` | runs every case end-to-end through the workflow via `act` |
| `.github/workflows/semantic-version-bumper.yml` | CI/CD pipeline |

## Usage

```bash
bun run src/cli.ts \
  --version-file package.json \
  --commits-file commits.txt \
  --changelog CHANGELOG.md \
  [--date 2026-06-26]
```

Output (stable, machine-parseable):

```
PREVIOUS_VERSION=1.1.0
NEW_VERSION=1.2.0
BUMP=minor
```

## Testing

```bash
bun test tests/        # unit suite (TDD)
bun test meta/         # workflow structure + actionlint
bun run act-harness.ts # full pipeline through `act`, writes act-result.txt
```

The act harness builds an isolated git repo per case, runs `act push --rm`,
and asserts the exact `NEW_VERSION` / `BUMP` values plus `Job succeeded` for
every job. All output is captured in `act-result.txt`.
