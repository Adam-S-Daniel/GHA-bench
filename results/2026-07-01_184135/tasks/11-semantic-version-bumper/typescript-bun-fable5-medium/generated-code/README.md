# semantic-version-bumper

Bumps a semantic version based on conventional commits and generates a
changelog entry. Built with TypeScript + Bun using red/green TDD.

Rules: any breaking change (`type!:` or a `BREAKING CHANGE:` footer) → major,
else any `feat` → minor, else any `fix` → patch, else no bump.

## Usage

```sh
bun run src/cli.ts \
  --version-file package.json \   # or a plain VERSION file
  --commits commits.txt \         # one commit subject per line (git log --pretty=%s)
  --changelog CHANGELOG.md \
  --date 2026-07-01 \             # optional, defaults to today
  --dry-run                       # optional, compute only
```

The new version is printed as the last line of stdout. With no releasable
commits the version file is left untouched and the CLI exits 0.

## Layout

- `src/semver.ts` — parse/format/bump `MAJOR.MINOR.PATCH`
- `src/commits.ts` — conventional-commit parsing + bump decision
- `src/changelog.ts` — markdown changelog entry generation/prepending
- `src/versionfile.ts` — read/write package.json or plain VERSION files
- `src/cli.ts` — command-line entry point
- `fixtures/` — mock commit logs used by both unit tests and CI
- `tests/` — `bun test` suite (unit, CLI subprocess, workflow structure)
- `scripts/run-act-tests.ts` — runs every fixture case through the GitHub
  Actions workflow with `act` and asserts exact expected versions

## Testing

```sh
bun test                          # unit + CLI + workflow-structure tests
bun run scripts/run-act-tests.ts  # full pipeline via act (writes act-result.txt)
```

The workflow at `.github/workflows/semantic-version-bumper.yml` runs the unit
tests, then a matrix job per fixture case (feat → 1.3.0, fix → 1.2.4,
breaking → 2.0.0, none → unchanged) asserting exact results.
