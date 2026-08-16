# Semantic Version Bumper - PowerShell TDD Implementation

A PowerShell implementation of semantic version bumping with conventional commits analysis, using red/green TDD methodology.

## Overview

This project provides:
1. **PowerShell functions** for semantic version management
2. **Comprehensive Pester tests** with 100% passing rate (19 tests)
3. **GitHub Actions workflow** for automated version bumping in CI/CD
4. **Full test coverage** using TDD: fail-first, implement, refactor

## Features

- **Parse versions** from `package.json` or `version.txt` files
- **Analyze commits** using conventional commit format (feat, fix, BREAKING CHANGE)
- **Calculate version bumps** following semantic versioning:
  - `BREAKING CHANGE` → major version bump (e.g., 1.2.3 → 2.0.0)
  - `feat:` → minor version bump (e.g., 1.2.3 → 1.3.0)
  - `fix:` → patch version bump (e.g., 1.2.3 → 1.2.4)
- **Update version files** with backup creation
- **Generate changelog entries** categorized by type
- **Main orchestration function** that handles the complete workflow

## Files

```
├── Semantic-Version-Bumper.ps1       # Implementation (6 functions)
├── Semantic-Version-Bumper.Tests.ps1 # Pester tests (19 test cases)
├── run-tests.ps1                     # Simple test runner
├── test-runner.ps1                   # Multi-scenario test executor
├── .github/workflows/
│   └── semantic-version-bumper.yml   # GitHub Actions workflow
├── README.md                         # This file
└── act-result.txt                    # Workflow test execution log
```

## Functions

### `Parse-SemanticVersion`
Reads current version from package.json (.version property) or version.txt (plain text).

**Parameters:**
- `FilePath`: Path to version file (.json or .txt)

**Returns:** Version string (e.g., "1.0.0")

### `Get-VersionBumpType`
Analyzes commit log to determine the highest priority version bump needed.

**Parameters:**
- `CommitLogPath`: Path to file with one commit message per line

**Returns:** "major", "minor", "patch", or "none"

**Logic:**
- If any commit matches "BREAKING CHANGE" → returns "major"
- Else if any commit starts with "feat:" → returns "minor"  
- Else if any commit starts with "fix:" → returns "patch"
- Else → returns "none"

### `Get-NextSemanticVersion`
Calculates the next semantic version given current version and bump type.

**Parameters:**
- `CurrentVersion`: Current version string (format: major.minor.patch)
- `BumpType`: One of "major", "minor", "patch", "none"

**Returns:** New version string following semantic versioning rules

### `Update-VersionInFile`
Updates the version in a version file and creates a backup.

**Parameters:**
- `FilePath`: Path to version file
- `NewVersion`: New version string

**Side Effects:**
- Creates `.bak` backup of original file
- Updates version in the file
- Uses UTF-8 encoding

### `Generate-ChangelogEntry`
Creates a formatted changelog entry from commits.

**Parameters:**
- `CommitLogPath`: Path to commit log file
- `NewVersion`: Version being released
- `Date`: Release date (datetime object)

**Returns:** Formatted changelog text with sections for Features and Fixes

### `Invoke-SemanticVersionBump`
Main orchestration function that coordinates the full bump workflow.

**Parameters:**
- `VersionFilePath`: Path to version file to update
- `CommitLogPath`: Path to commit log file

**Returns:** Hashtable with:
- `OldVersion`: Previous version
- `NewVersion`: New version
- `BumpType`: Type of bump performed
- `Changelog`: Generated changelog entry
- `VersionFile`: Path to version file updated

## Test Coverage

All 19 tests pass using Pester framework:

### Parse-SemanticVersion (3 tests)
- ✓ Parse version from package.json
- ✓ Parse version from version.txt  
- ✓ Throw on missing file

### Get-VersionBumpType (5 tests)
- ✓ Detect patch for fix commit
- ✓ Detect minor for feat commit
- ✓ Detect major for breaking change
- ✓ Prefer highest bump level
- ✓ Return none for non-conventional commits

### Get-NextSemanticVersion (5 tests)
- ✓ Bump patch version
- ✓ Bump minor and reset patch
- ✓ Bump major and reset minor/patch
- ✓ Handle 0.x.x versions
- ✓ No change for "none" bump type

### Update-VersionInFile (3 tests)
- ✓ Update package.json
- ✓ Update version.txt
- ✓ Create backup file

### Generate-ChangelogEntry (2 tests)
- ✓ Generate changelog with version
- ✓ Categorize commits by type

### Invoke-SemanticVersionBump (1 test)
- ✓ Complete full workflow

## Running Tests

### Unit Tests
```powershell
# Run all Pester tests
Invoke-Pester -Path ./Semantic-Version-Bumper.Tests.ps1

# Run with detailed output
Invoke-Pester -Path ./Semantic-Version-Bumper.Tests.ps1 -Output Detailed
```

### GitHub Actions Workflow
```bash
# Validate workflow YAML
actionlint .github/workflows/semantic-version-bumper.yml

# Execute workflow locally with act
act push --rm -W .github/workflows/semantic-version-bumper.yml

# View execution log
cat act-result.txt
```

## GitHub Actions Workflow

The workflow at `.github/workflows/semantic-version-bumper.yml`:

**Triggers:**
- Push to main/master
- Pull requests
- Manual workflow_dispatch
- Daily schedule possible

**Jobs:**

1. **test-and-bump** (Test and Bump Version)
   - Runs on ubuntu-latest
   - Sets up PowerShell environment
   - Runs unit tests with Pester
   - Creates test fixtures (package.json + commits.log)
   - Executes version bump
   - Verifies version file was updated
   - Saves workflow results

2. **actionlint** (Validate Workflow YAML)
   - Validates workflow syntax
   - Checks action references
   - Ensures correct YAML format

**Permissions:**
- `contents: read` - Minimal for checking out code

## Example Usage

```powershell
# Source the implementation
. ./Semantic-Version-Bumper.ps1

# Create test files
$packageJson = @{ version = "1.0.0"; name = "myapp" } | ConvertTo-Json
Set-Content -Path ./package.json -Value $packageJson

$commits = @(
    "feat: add new dashboard",
    "fix: resolve memory leak"
) -join "`n"
Set-Content -Path ./commits.log -Value $commits

# Run the full workflow
$result = Invoke-SemanticVersionBump `
    -VersionFilePath ./package.json `
    -CommitLogPath ./commits.log

# Output results
Write-Output "Old Version: $($result.OldVersion)"
Write-Output "New Version: $($result.NewVersion)"  # 1.1.0 (feat = minor bump)
Write-Output "Bump Type: $($result.BumpType)"      # minor
Write-Output $result.Changelog
```

## Development Notes

### TDD Approach
This project was built using red/green TDD:
1. **Red:** Write test that fails (function doesn't exist)
2. **Green:** Implement minimum code to pass test
3. **Refactor:** Clean up implementation while keeping tests passing

### Pester Scoping
Tests use `BeforeAll` blocks to define functions in the correct scope for Pester test isolation. This ensures functions are available within `Describe` and `It` blocks.

### Act Workflow Testing
The workflow is validated in two ways:
1. **Syntax:** `actionlint` ensures valid YAML and action references
2. **Execution:** `act` runs the workflow in an isolated Docker container with pwsh

### PowerShell Version Requirements
- PowerShell 7.0+ (pwsh)
- Pester 6.0+ for testing
- No external dependencies for the implementation

## Workflow Execution Results

The `act-result.txt` file contains the complete execution log of the GitHub Actions workflow run through `act`. It demonstrates:

✓ All unit tests pass (19/19)
✓ Workflow jobs succeed
✓ Version correctly bumped from 1.0.0 to 1.1.0
✓ Changelog generated with categorized commits
✓ Version file updated with backup created
✓ actionlint validation passed

## License

This is a demonstration project for PowerShell scripting and GitHub Actions CI/CD.
