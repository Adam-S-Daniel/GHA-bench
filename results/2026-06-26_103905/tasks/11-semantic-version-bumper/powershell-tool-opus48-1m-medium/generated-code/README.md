# Semantic Version Bumper (PowerShell)

Reads a semantic version (from a plain `version.txt` or a `package.json`), inspects
[Conventional Commits](https://www.conventionalcommits.org/) to decide the next
version (`feat` → minor, `fix` → patch, breaking change → major), updates the version
file, prepends a `CHANGELOG.md` entry, and prints the new version.

## Layout

| Path | Purpose |
| --- | --- |
| `src/SemanticVersionBumper.psm1` | Core logic (pure, unit-tested functions). |
| `Invoke-Bumper.ps1` | CLI orchestrator used by the CI workflow. |
| `tests/SemanticVersionBumper.Tests.ps1` | Pester unit tests (built red/green TDD). |
| `tests/Workflow.Tests.ps1` | Workflow structure + end-to-end `act` tests. |
| `tests/fixtures/*` | Mock commit logs + version files per test case. |
| `.github/workflows/semantic-version-bumper.yml` | CI/CD pipeline. |

## Usage

```pwsh
./Invoke-Bumper.ps1 -VersionPath version.txt -CommitLogPath commits.txt -ChangelogPath CHANGELOG.md
```

Output contract (stdout, also written to `$GITHUB_OUTPUT` in CI):

```
PREVIOUS_VERSION=1.1.0
BUMP_TYPE=minor
NEW_VERSION=1.2.0
```

The commit log lists one commit subject per line, or multiple multi-line commit
messages separated by a line containing only `---` (so `BREAKING CHANGE:` footers
survive).

## Bump precedence

`breaking (! or BREAKING CHANGE:)` → **major** > `feat` → **minor** > `fix` →
**patch** > anything else → **none** (version unchanged).

## Testing

```pwsh
Invoke-Pester -Path tests        # all unit + workflow tests
```

The workflow tests drive every functional case through the real pipeline with
`act` (nektos/act) and assert exact expected versions; their combined output is
saved to `act-result.txt`.
```pwsh
actionlint .github/workflows/semantic-version-bumper.yml
```
