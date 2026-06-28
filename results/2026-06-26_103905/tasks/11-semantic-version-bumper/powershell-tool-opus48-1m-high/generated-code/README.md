# Semantic Version Bumper (PowerShell)

A small, test-driven PowerShell tool that reads a semantic version from a file
(`version.txt` or `package.json`), inspects Conventional Commit messages,
computes the next version, updates the version file, and prepends a changelog
entry.

## Bump rules (Conventional Commits)

| Commit                                            | Bump    |
| ------------------------------------------------- | ------- |
| `feat!:` / `fix(scope)!:` / `BREAKING CHANGE:`    | `major` |
| `feat:` / `feat(scope):`                          | `minor` |
| `fix:` / `fix(scope):`                            | `patch` |
| anything else (`chore`, `docs`, ...)              | `none`  |

The highest-precedence bump across all commits wins.

## Files

| File                              | Purpose                                                      |
| --------------------------------- | ----------------------------------------------------------- |
| `SemanticVersionBumper.ps1`       | Function library (parse, classify, compute, changelog, write) |
| `Invoke-Bump.ps1`                 | CLI entry point used locally and by CI                      |
| `SemanticVersionBumper.Tests.ps1` | Pester unit tests (24) for the library                      |
| `Workflow.Tests.ps1`              | Pester structure tests for the workflow                     |
| `Invoke-ActTests.ps1`             | End-to-end harness running the workflow through `act`       |
| `fixtures/`                       | Mock commit logs used as test fixtures                      |
| `.github/workflows/semantic-version-bumper.yml` | CI/CD pipeline                                |

## Usage

```powershell
pwsh ./Invoke-Bump.ps1 -VersionFile version.txt -CommitLogFile commits.txt -ChangelogFile CHANGELOG.md
```

Output includes machine-readable lines `NEW_VERSION=<x.y.z>` and
`BUMP_TYPE=<type>`, and (under GitHub Actions) populates step outputs
`new_version` / `bump_type`.

## Testing

```powershell
# Unit + structure tests (fast, no Docker)
Invoke-Pester -Path ./SemanticVersionBumper.Tests.ps1, ./Workflow.Tests.ps1

# Full pipeline through act (Docker required); writes act-result.txt
pwsh ./Invoke-ActTests.ps1
```

The tool was built red/green TDD: each unit of functionality began as a
failing Pester test, followed by the minimum implementation to make it pass.
