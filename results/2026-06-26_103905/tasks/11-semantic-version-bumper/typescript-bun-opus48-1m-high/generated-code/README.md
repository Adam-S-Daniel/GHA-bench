# Semantic Version Bumper

A small TypeScript + [Bun](https://bun.sh) tool that reads a semantic version,
inspects a [Conventional Commits](https://www.conventionalcommits.org/) log,
decides the next version (`feat` → minor, `fix` → patch, breaking → major),
updates the version file, and writes a changelog entry.

## Layout

| Path | Purpose |
|------|---------|
| `src/semver.ts` | Parse / format / compare / bump semantic versions (pure). |
| `src/commits.ts` | Parse conventional commit messages; reduce a log to one bump. |
| `src/changelog.ts` | Render a "Keep a Changelog" entry from parsed commits. |
| `src/bumper.ts` | Orchestration + CLI: read files, compute, write back, report. |
| `tests/` | Unit tests (run inside CI). Pure, fast, no `act`/Docker. |
| `integration/` | Workflow-structure checks + the `act` harness (local only). |
| `fixtures/` | Mock commit logs + version files used as test cases. |
| `.github/workflows/semantic-version-bumper.yml` | The CI/CD pipeline. |

## Usage

```bash
bun run src/bumper.ts \
  --version-file VERSION \
  --commits commits.log \
  --changelog CHANGELOG.md \
  [--date 2026-06-27] [--dry-run]
```

- `--version-file` may be a plain text version file **or** a `package.json`
  (only its `.version` field is rewritten; other fields are preserved).
- Machine-readable output is printed to **stdout**:
  `PREVIOUS_VERSION=…`, `NEW_VERSION=…`, `BUMP=…`. A human summary goes to stderr.

### Commit log formats

- **One commit per line** (e.g. `git log --format=%s`).
- **Record-delimited**: commits separated by a line containing only `---`,
  which preserves multi-line bodies/footers such as `BREAKING CHANGE:`.

## Testing (red/green TDD)

```bash
bun test tests/                       # fast unit suite
bun test integration/workflow-structure.test.ts   # YAML/actionlint checks
bun test integration/act.test.ts      # full pipeline via nektos/act (needs Docker)
bun test                              # everything
```

The `integration/act.test.ts` harness runs the **actual GitHub Actions
workflow** for each fixture via `act push --rm`, appends every run's output to
`act-result.txt`, and asserts the exact next version, bump type, and
`Job succeeded` for each case.

## CI/CD

`.github/workflows/semantic-version-bumper.yml` checks out the repo, installs
Bun, runs the unit suite, then runs the bumper against `VERSION` + `commits.log`
and reports the result. It triggers on `push`, `pull_request`, a weekly
`schedule`, and manual `workflow_dispatch` (with a `dry_run` toggle).
