# Semantic Version Bumper (PowerShell)

Bumps a semantic version based on conventional commit messages, updates the
version file (plain `version.txt` or `package.json`), and prepends a grouped
changelog entry to `CHANGELOG.md`.

Bump rules (highest across all commits wins):

| Commit pattern                              | Bump  |
|---------------------------------------------|-------|
| `BREAKING CHANGE` footer or `type!:` bang   | major |
| `feat:` / `feat(scope):`                    | minor |
| `fix:` / `fix(scope):`                      | patch |
| anything else (`chore:`, `docs:`, ...)      | none  |

## Layout

- `src/VersionBumper.psm1` — module: `Get-BumpType`, `Step-Version`,
  `Get-CurrentVersion`, `Set-CurrentVersion`, `New-ChangelogEntry`,
  `Invoke-VersionBump`.
- `Invoke-VersionBump.ps1` — CLI entry point; prints `NEW_VERSION=x.y.z`
  and writes `new_version`/`bump_type` to `$GITHUB_OUTPUT` in CI.
- `fixtures/commits-*.txt` — mock commit logs used as test fixtures.
- `tests/VersionBumper.Tests.ps1` — unit tests (built red/green TDD).
- `tests/Workflow.Tests.ps1` — workflow structure tests (YAML parse,
  actionlint, path references).
- `tests/ActPipeline.Tests.ps1` — end-to-end tests running every case
  through the workflow with `act push --rm`; appends output to
  `act-result.txt`. Set `VB_SKIP_ACT=1` to skip the Docker runs.
- `.github/workflows/semantic-version-bumper.yml` — CI pipeline: Pester
  unit-test job, then a bump job that runs the script and surfaces the new
  version as a step output.

## Usage

```powershell
./Invoke-VersionBump.ps1 -VersionFile version.txt -CommitLog commits.txt -ChangelogPath CHANGELOG.md
```

## Tests

```powershell
Invoke-Pester -Path tests            # everything (3 act/Docker runs included)
$env:VB_SKIP_ACT='1'; Invoke-Pester -Path tests   # skip the act runs
```
