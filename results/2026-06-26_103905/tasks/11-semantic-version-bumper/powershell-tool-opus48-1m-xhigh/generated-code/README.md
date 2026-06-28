# Semantic Version Bumper (PowerShell)

A small, test-driven PowerShell tool that:

1. Reads the current semantic version from a version file or `package.json`.
2. Determines the next version from Conventional Commit messages
   (`feat` → minor, `fix` → patch, breaking change → major).
3. Updates the version file in place (preserving its format).
4. Generates a grouped `CHANGELOG.md` entry from the commits.
5. Outputs the new version.

It is wired into a real GitHub Actions pipeline (`.github/workflows/semantic-version-bumper.yml`)
that is validated with `actionlint` and exercised end-to-end with
[`nektos/act`](https://github.com/nektos/act).

## Layout

| Path | Purpose |
| --- | --- |
| `src/SemanticVersionBumper.ps1` | Core library (pure functions, no load-time side effects). |
| `bump-version.ps1` | CLI entry point the workflow runs. Emits a stable `KEY=value` contract. |
| `version.txt` | Default version file the workflow bumps (override-able). |
| `commits.txt` | Default commit-log fixture the workflow reads. |
| `CHANGELOG.md` | Changelog the tool prepends entries to. |
| `fixtures/` | Mock commit logs for each bump scenario (feat / fix / breaking / none). |
| `tests/SemanticVersionBumper.Tests.ps1` | Pester unit tests (TDD). |
| `tests/Workflow.Tests.ps1` | Host-side workflow structure tests (YAML parse, references, actionlint). |
| `tests/Act.Integration.Tests.ps1` | Integration tests — every case runs through the workflow via `act`. |
| `run-act-tests.ps1` | Convenience wrapper for the act integration harness. |
| `.github/workflows/semantic-version-bumper.yml` | The CI/CD pipeline. |

## How the bump is decided

Each commit is parsed as a Conventional Commit (`type(scope)!: description`).
The highest-precedence signal across all commits wins:

| Signal | Bump |
| --- | --- |
| `feat!: …`, or a `BREAKING CHANGE` token | **major** |
| `feat: …` / `feat(scope): …` | **minor** |
| `fix: …` / `fix(scope): …` | **patch** |
| anything else (`chore`, `docs`, …) | **none** |

Commit logs are read from a fixture file (one commit subject per line; `#`
comments and blank lines ignored) when one is supplied, otherwise from real
`git log` history since the last tag — so the same tool is deterministic in
tests and useful in a live pipeline.

## Running locally

```bash
# Fast unit + structure tests (no Docker needed)
pwsh -c "Invoke-Pester -Path tests/SemanticVersionBumper.Tests.ps1,tests/Workflow.Tests.ps1"

# Run the bumper by hand
pwsh ./bump-version.ps1 -VersionFile version.txt -CommitLogFile commits.txt

# Full integration: every case through the GitHub Actions workflow via act
pwsh ./run-act-tests.ps1            # writes act-result.txt
```

## Output contract (stdout)

`bump-version.ps1` prints a stable, greppable contract used by the pipeline and
the integration tests:

```
PREVIOUS_VERSION=1.1.0
BUMP_TYPE=minor
NEW_VERSION=1.2.0
CHANGED=true
```

Inside GitHub Actions it also writes `previous_version` / `new_version` /
`bump_type` / `changed` step outputs and a job summary.

## CI/CD pipeline

`.github/workflows/semantic-version-bumper.yml` runs on push, pull_request,
manual dispatch (with an overridable commit-log fixture) and a weekly schedule.
It has two jobs:

1. **test** — installs/imports Pester and runs the unit tests.
2. **bump** — (`needs: test`) runs `bump-version.ps1`, prints the result, and
   shows the updated changelog.

Permissions are least-privilege (`contents: read`); the pipeline computes and
writes files inside the workspace but does not push, so it needs no secrets and
runs cleanly in an isolated container. A production deployment could add a
final commit/tag/push step guarded by `contents: write` and `GITHUB_TOKEN`.
