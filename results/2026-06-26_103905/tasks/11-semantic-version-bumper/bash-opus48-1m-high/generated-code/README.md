# Semantic Version Bumper

A small Bash tool that reads a semantic version from a `VERSION` file or a
`package.json`, inspects [conventional commit](https://www.conventionalcommits.org/)
messages to decide the next release, updates the version file, prepends a
changelog entry, and prints the new version.

## Bump rules

| Commit signal                                             | Bump    |
| --------------------------------------------------------- | ------- |
| `feat!: …`, `fix!: …`, any `type!:`, or `BREAKING CHANGE:` footer | major |
| `feat: …`                                                 | minor   |
| `fix: …`                                                  | patch   |
| anything else (`chore`, `docs`, `style`, …)               | ignored |

The highest-precedence signal across all commits wins (major > minor > patch).
If nothing is releasable the current version is printed unchanged and no files
are written.

## Usage

```bash
./semver-bump.sh \
  --version-file VERSION \
  --commits commits.txt \
  --changelog CHANGELOG.md \
  [--date YYYY-MM-DD] [--dry-run]
```

The new version is printed to **stdout**; human-readable status goes to stderr.

## Files

| Path                                          | Purpose                                              |
| --------------------------------------------- | ---------------------------------------------------- |
| `semver-bump.sh`                              | The tool. Sourcing it exposes its functions for tests without running `main()`. |
| `test/semver-bump.bats`                       | Unit tests (24), built red/green via TDD.            |
| `test/workflow.bats`                          | Workflow structure tests (12): triggers, jobs, steps, file references, actionlint. |
| `fixtures/<case>/`                            | Mock commit logs + version files used as test fixtures. |
| `.github/workflows/semantic-version-bumper.yml` | CI pipeline; a job matrix runs every fixture case.   |
| `run-act-tests.sh`                            | Integration harness: runs the matrix through `act`, saves `act-result.txt`, asserts exact expected versions and per-job success. |

## Testing

```bash
# Unit + structure tests (fast, no Docker)
bats test/

# Static checks
shellcheck semver-bump.sh run-act-tests.sh
actionlint .github/workflows/semantic-version-bumper.yml

# Full pipeline through GitHub Actions locally (requires Docker + act)
bash run-act-tests.sh   # writes act-result.txt
```

The six fixture cases and their known-good expected outputs:

| Case              | Input version (file)         | Commits                       | Expected |
| ----------------- | ---------------------------- | ----------------------------- | -------- |
| `patch`           | `1.1.0` (VERSION)            | `fix:`                        | `1.1.1`  |
| `minor`           | `1.1.0` (VERSION)            | `feat:` + `fix:`              | `1.2.0`  |
| `major`           | `1.1.0` (VERSION)            | `feat!:`                      | `2.0.0`  |
| `pkgjson`         | `0.3.4` (package.json)       | `feat:`                       | `0.4.0`  |
| `breaking-footer` | `2.5.1` (VERSION)            | `fix:` + `BREAKING CHANGE:`   | `3.0.0`  |
| `none`            | `1.1.0` (VERSION)            | `chore:`/`docs:` only         | `1.1.0`  |
