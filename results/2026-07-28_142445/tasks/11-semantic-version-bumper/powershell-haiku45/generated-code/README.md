# Semantic Version Bumper

A PowerShell implementation of semantic version bumping based on conventional commit messages, tested with red-green-refactor TDD methodology and integrated with GitHub Actions.

## Features

- **Semantic Version Parsing**: Parse version strings (e.g., "1.2.3", "v1.2.3")
- **Conventional Commit Analysis**: Automatically detect version bump type from commit messages
  - `fix:` → Patch bump (1.2.3 → 1.2.4)
  - `feat:` → Minor bump (1.2.3 → 1.3.0)
  - `BREAKING CHANGE:` or `feat!:` → Major bump (1.2.3 → 2.0.0)
- **Changelog Generation**: Auto-generate changelog entries from commits
- **Package.json Updates**: Automatically update version in package.json files
- **GitHub Actions Integration**: Full workflow with testing and validation
- **Comprehensive Testing**: 15 unit tests using Pester framework

## Files

### Core Implementation
- **`version-bumper.ps1`** - Core library with all version manipulation functions
- **`bump-version.ps1`** - CLI entry point for using the version bumper
- **`test-fixtures.ps1`** - Mock commit data for testing various scenarios

### Testing
- **`test-version-bumper.ps1`** - Comprehensive Pester test suite (15 tests)
- **`run-act-tests.ps1`** - Test harness for running GitHub Actions workflow tests
- **`run-workflow-tests.sh`** - Shell script for running 3 act-based workflow tests

### GitHub Actions
- **`.github/workflows/semantic-version-bumper.yml`** - Complete CI/CD workflow
  - Runs Pester tests
  - Bumps version based on commits
  - Validates workflow structure
  - Exports results to JSON

### Output
- **`act-result.txt`** - Captured output from all act workflow tests

## Quick Start

### Run Unit Tests
```powershell
Invoke-Pester test-version-bumper.ps1 -Output Detailed
```

### Bump Version Manually
```powershell
. ./bump-version.ps1 -PackageJsonPath package.json -CommitBase "HEAD~10"
```

### Run GitHub Actions Workflow Locally
```bash
# List available jobs
act push --list

# Run all jobs
act push

# Run specific job
act push -j bump-version
```

### Run All Tests (including act)
```bash
bash run-workflow-tests.sh
```

## Architecture

### Version Parsing
- `Parse-SemanticVersion` - Parses version strings into structured objects
- `Format-Version` - Converts version objects back to strings

### Conventional Commits
- `Parse-ConventionalCommits` - Analyzes commit messages to determine bump type
- Supports multi-line commit messages with body/footer
- Recognizes both `BREAKING CHANGE:` footer and `feat!:` syntax

### Version Bumping
- `Get-NextVersion` - Calculates next version based on commit type
- Follows semantic versioning rules (major.minor.patch)

### File Operations
- `Update-PackageJsonVersion` - Updates package.json version field
- `Get-GitCommitsSince` - Retrieves commits from git history
- `Generate-ChangelogEntry` - Creates formatted changelog entries
- `Invoke-SemanticVersionBump` - Main orchestration function

## Test Coverage

### Unit Tests (15 total)
1. Parse valid semantic version strings
2. Parse versions with leading 'v'
3. Reject invalid version formats
4. Bump patch for fix commits
5. Bump minor for feature commits
6. Bump major for breaking changes
7. Format versions correctly
8. Identify feat commits
9. Identify fix commits
10. Identify breaking changes
11. Prioritize breaking > feat > fix
12. Generate changelog entries
13. Update package.json
14. Retrieve git commits
15. Execute full semantic bump workflow

### Integration Tests
- 3 complete act-based workflow test cases
- Test case 1: Patch bump (fix commits)
- Test case 2: Minor bump (feature commits)
- Test case 3: Major bump (breaking changes)
- All tests pass with code 0 and "Job succeeded" status

## TDD Approach

This implementation follows red-green-refactor TDD methodology:

1. **Red**: Write failing tests first
2. **Green**: Implement minimum code to pass tests
3. **Refactor**: Improve implementation while keeping tests passing

Each function was implemented incrementally:
- Started with version parsing
- Added version comparison logic
- Implemented conventional commit analysis
- Added file I/O operations
- Integrated everything into main workflow

## GitHub Actions Workflow

The workflow consists of 2 jobs:

### Job 1: bump-version
- Checks out code with full git history
- Runs Pester test suite (must pass)
- Bumps version based on commits
- Exports results to JSON
- Supports manual trigger with custom inputs

### Job 2: workflow-validation
- Verifies all required script files exist
- Validates workflow YAML structure
- Confirms workflow readiness

Both jobs use the `act-ubuntu-pwsh:latest` Docker image with pwsh and Pester pre-installed.

## Workflow Validation

✅ **actionlint validation**: Passes with no errors
- Valid YAML syntax
- Correct action references
- Proper permissions and environment setup
- Compatible with act execution

## Testing Results

### Local Tests
```
Tests Passed: 15
Tests Failed: 0
Pester v6.0.1
All tests completed successfully
```

### Workflow Tests (via act)
```
Test 1: patch-bump ✓
Test 2: minor-bump ✓
Test 3: major-bump ✓

All jobs: Job succeeded
Exit codes: All 0
act-result.txt: Generated with full output
```

## Exit Codes

- **0**: Success (all tests passed, version bumped)
- **1**: Failure (test failure, file not found, invalid version format)

## Error Handling

- Validates file paths before operations
- Gracefully handles missing commits
- Provides meaningful error messages
- Handles git repository state issues

## Notes

- The script assumes conventional commit format strictly
- Version bumping defaults to patch bump if no commits found
- Changelog entries preserve date in YYYY-MM-DD format
- Multiple commits of same type within one bump are combined
- Works with both Windows/Linux PowerShell 7+ (pwsh)
