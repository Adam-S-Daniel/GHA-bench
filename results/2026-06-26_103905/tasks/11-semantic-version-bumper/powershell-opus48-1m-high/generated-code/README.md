# Semantic Version Bumper (PowerShell)

Parses a version file (plain `VERSION` or `package.json`), reads conventional
commit messages, computes the next semantic version (`feat` → minor, `fix` →
patch, breaking → major), updates the version file, prepends a changelog entry,
and prints the new version. Built with red/green TDD using Pester.

## Layout

| Path | Purpose |
| --- | --- |
| `src/SemanticVersionBumper.psm1` | Core module (parse, bump, changelog). |
| `Invoke-VersionBump.ps1` | CLI entry point used by CI. |
| `tests/SemanticVersionBumper.Tests.ps1` | Pester unit/integration tests for the module. |
| `tests/Workflow.Tests.ps1` | Workflow structure tests + `act` pipeline harness. |
| `fixtures/*.log` | Mock commit logs (`<hash> <subject>` per line). |
| `.github/workflows/semantic-version-bumper.yml` | CI/CD workflow. |

## Usage

```pwsh
./Invoke-VersionBump.ps1 -VersionFile VERSION -CommitLog commits.log
```

Commit-log format mirrors `git log --pretty=format:"%h %s"`; blank lines and
`#` comments are ignored. Breaking changes are flagged by `!` before the colon
(`feat!:`, `feat(api)!:`) or a `BREAKING CHANGE` token.

## Testing

```pwsh
Invoke-Pester -Path ./tests/SemanticVersionBumper.Tests.ps1   # unit tests (fast)
Invoke-Pester -Path ./tests/Workflow.Tests.ps1                # structure + act pipeline
```

The `Workflow.Tests.ps1` harness runs every case end-to-end through the GitHub
Actions workflow via `act`, asserts exact bumped versions, and writes all output
to `act-result.txt`.
