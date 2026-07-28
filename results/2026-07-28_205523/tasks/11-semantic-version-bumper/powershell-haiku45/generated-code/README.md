# Semantic Version Bumper - PowerShell Implementation

A comprehensive PowerShell implementation of semantic version bumping following conventional commit specifications.

## Overview

This solution implements semantic versioning with the following features:
- **TDD-driven development** using red/green testing methodology
- **Pester test framework** with 17 comprehensive test cases (all passing)
- **Conventional commit parsing** (feat, fix, BREAKING CHANGE)
- **Automatic version bumping** (major, minor, patch)
- **Changelog generation** organized by commit type
- **GitHub Actions workflow** for CI/CD integration
- **Act validation** for local testing

## Architecture

### Core Components

#### SemanticVersionBumper.ps1
The main module containing all versioning logic:

- **Parse-SemanticVersion**: Parses semantic version strings (e.g., "1.2.3")
- **Read-VersionFromFile**: Reads version from text files
- **Read-VersionFromPackageJson**: Reads version from package.json
- **Get-CommitType**: Identifies commit type (feat/fix/breaking)
- **Bump-Version**: Increments version numbers based on bump type
- **Determine-BumpType**: Analyzes commits to determine version bump priority
- **Get-ConventionalCommits**: Fetches commits since last version tag
- **Generate-Changelog**: Creates formatted changelog entries
- **Update-VersionFile**: Writes new version to version file
- **Invoke-SemanticVersionBump**: Main orchestrator function

#### SemanticVersionBumper.Tests.ps1
Comprehensive test suite with 17 test cases organized by context:

1. **Version Parsing** (3 tests)
   - Parse semantic version strings
   - Read from package.json
   - Read from version.txt

2. **Commit Message Parsing** (4 tests)
   - Identify feat commits
   - Identify fix commits
   - Detect breaking changes
   - Handle commit bodies

3. **Version Bumping** (7 tests)
   - Major version on breaking changes
   - Minor version on features
   - Patch version on fixes
   - Bump priority rules

4. **Changelog Generation** (2 tests)
   - Generate changelog entries
   - Organize by commit type

5. **Integration** (1 test)
   - End-to-end version bump workflow

#### GitHub Actions Workflow (.github/workflows/semantic-version-bumper.yml)

**Test Job:**
- Runs Pester test suite
- All 17 tests pass
- Verifies code functionality

**Bump Version Job:**
- Triggered on push to main/master
- Requires test job to pass
- Supports both package.json and version.txt
- Generates CHANGELOG.md
- Commits and attempts to push changes

## Test Results

### Local Testing
```
Tests Passed: 17
Tests Failed: 0
Execution Time: ~1.2 seconds
```

### Act Testing (CI/CD)
All three test scenarios pass through act:

1. **Feature Commit (Minor Bump)**
   - Input: version 1.0.0 + feat commit
   - Output: version 1.1.0 ✓

2. **Fix Commit (Patch Bump)**
   - Input: version 2.0.0 + fix commit
   - Output: version 2.0.1 ✓

3. **Breaking Change (Major Bump)**
   - Input: version 1.0.0 + feat! commit
   - Output: version 2.0.0 ✓

### Validation
- **actionlint**: PASSED
- **Workflow Structure**: PASSED
- **Script References**: PASSED

## Usage

### Local Usage

#### Run all tests:
```powershell
Invoke-Pester SemanticVersionBumper.Tests.ps1
```

#### Bump version manually:
```powershell
. .\SemanticVersionBumper.ps1
Invoke-SemanticVersionBump -VersionFile "package.json" -ChangelogFile "CHANGELOG.md"
```

#### Use the entry point script:
```powershell
.\bump-version.ps1 -VersionFile "package.json" -OutputVersion
```

### CI/CD Integration

The workflow automatically:
1. Runs tests on every push and pull request
2. Bumps version on push to main/master (if tests pass)
3. Updates CHANGELOG.md
4. Commits changes with semantic versioning commit message

## Conventional Commit Format

The implementation recognizes:
- `feat: description` - Feature (bumps minor version)
- `fix: description` - Bug fix (bumps patch version)
- `feat!: description` or `BREAKING CHANGE:` - Breaking change (bumps major version)

## Implementation Details

### TDD Methodology

This solution follows red/green TDD:
1. **Red Phase**: Write failing tests
2. **Green Phase**: Implement minimum code to pass tests
3. **Refactor Phase**: Improve implementation quality

### Error Handling

- Validates semantic version format
- Handles missing/nonexistent files gracefully
- Provides meaningful error messages
- Safely handles git operations

### Performance

- Single-pass commit analysis
- Efficient regex matching for commit types
- No external dependencies (uses built-in PowerShell)

## Files

- `SemanticVersionBumper.ps1` - Main module (310 lines)
- `SemanticVersionBumper.Tests.ps1` - Test suite (210 lines)
- `bump-version.ps1` - Entry point script (25 lines)
- `.github/workflows/semantic-version-bumper.yml` - GitHub Actions workflow (77 lines)
- `test-harness.ps1` - Comprehensive test runner for act validation (210 lines)
- `act-result.txt` - Test execution results

## Test Coverage

- **Unit Tests**: 17 test cases covering all functions
- **Integration Tests**: End-to-end workflow with git repository
- **CI/CD Tests**: Three scenarios through act (GitHub Actions local runner)

## Key Features Demonstrated

✓ Red/Green TDD methodology
✓ Comprehensive test coverage
✓ Pester testing framework
✓ Mock data and fixtures
✓ GitHub Actions workflow
✓ actionlint validation
✓ Act integration testing
✓ Conventional commit parsing
✓ Semantic versioning logic
✓ Changelog generation

## Notes

- Pester is built into PowerShell 5.1+ and installed in GitHub Actions runners
- The implementation prioritizes correctness over complexity
- Comments explain non-obvious logic and important design decisions
- All code follows PowerShell conventions and best practices
