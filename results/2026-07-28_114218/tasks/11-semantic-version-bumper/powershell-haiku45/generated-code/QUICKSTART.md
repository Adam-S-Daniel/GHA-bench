# Quick Start Guide

## Installation

No installation required - just clone and run.

## Run Tests

```powershell
# Run all 26 unit tests
Invoke-Pester -Path SemanticVersionBumper.Tests.ps1

# Run tests with detailed output
Invoke-Pester -Path SemanticVersionBumper.Tests.ps1 -Verbose
```

## Bump Version

```powershell
# Basic usage with package.json in current directory
./bump-version.ps1 -CommitLog @"
feat: add new feature
fix: correct bug
"@

# Specify input and output files
./bump-version.ps1 `
  -PackageFile "path/to/package.json" `
  -CommitLog $commitMessages `
  -OutputFile "path/to/package.json" `
  -ChangelogFile "CHANGELOG.md"
```

## Test Locally with Docker (via act)

```bash
# Run test job
act push -j test

# Run integration test
act push -j integration

# Run all jobs
act push

# Run and clean up containers
act push --rm
```

## Examples

### Patch Version Bump
```powershell
./bump-version.ps1 -CommitLog "fix: correct button alignment"
# 1.0.0 → 1.0.1
```

### Minor Version Bump
```powershell
./bump-version.ps1 -CommitLog @"
feat(auth): add OAuth support
fix(ui): correct alignment
"@
# 1.0.0 → 1.1.0
```

### Major Version Bump
```powershell
./bump-version.ps1 -CommitLog @"
feat(api): refactor endpoints

BREAKING CHANGE: /api/v1 endpoints removed
"@
# 1.0.0 → 2.0.0
```

## Commit Format

The tool expects conventional commits:

```
type(scope): subject

body describing the change

BREAKING CHANGE: optional breaking change description
```

**Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

## Module Usage

```powershell
# Source the module
. .\SemanticVersionBumper.ps1

# Parse version
$version = ParseVersion -JsonContent $jsonString

# Parse commit
$commit = ParseCommitMessage -Message "feat(auth): add MFA"

# Determine next version
$next = DetermineNextVersion -CurrentVersion "1.0.0" -Commits $commits

# Generate changelog
$changelog = GenerateChangelog -Commits $commits -Version "1.1.0"
```

## Test Fixtures

```powershell
# Source fixtures
. .\test-fixtures.ps1

# Get mock commits
$commits = Get-MockCommits -Scenario "major-breaking"
$commits = Get-MockCommits -Scenario "mixed"
$commits = Get-MockCommits -Scenario "patch-only"
```

Available scenarios:
- `patch-only`
- `minor-feature`
- `major-breaking`
- `mixed`
- `complex-breaking`

## Verify Installation

```powershell
# Check files exist
Test-Path SemanticVersionBumper.ps1       # Should be $true
Test-Path SemanticVersionBumper.Tests.ps1 # Should be $true
Test-Path bump-version.ps1                # Should be $true
Test-Path package.json                    # Should be $true

# Run tests
Invoke-Pester -Path SemanticVersionBumper.Tests.ps1
# Should show: Tests Passed: 26
```

## GitHub Actions

The workflow automatically runs on:
- Push to main branch
- Pull requests
- Weekly schedule (Sunday at midnight UTC)
- Manual trigger (workflow_dispatch)

View results:
1. Go to GitHub Actions tab
2. Select "Semantic Version Bumper" workflow
3. Click on a run to see details

## Troubleshooting

**Tests fail**: Ensure PowerShell 7.0+ and Pester 6.0+ installed
```powershell
$PSVersionTable.PSVersion     # Should be 7.0+
Import-Module Pester -PassThru | Select Version  # Should be 6.0+
```

**act not found**: Install from https://github.com/nektos/act

**actionlint not found**: Install from https://github.com/rhysd/actionlint (optional for workflow validation)

## Next Steps

1. Review README.md for comprehensive documentation
2. Examine test file (SemanticVersionBumper.Tests.ps1) to understand behavior
3. Look at COMPLETION_SUMMARY.md for project status
4. Run tests locally to verify everything works
5. Test with act for GitHub Actions simulation
