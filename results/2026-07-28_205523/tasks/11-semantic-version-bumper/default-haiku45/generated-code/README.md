# Semantic Version Bumper

A TDD-based implementation of a semantic version bumper that follows conventional commits and semantic versioning.

## Overview

This project implements a complete solution for:
- Parsing semantic versions from `package.json` or `VERSION` files
- Analyzing git commits using conventional commit specification
- Determining version bumps (major/minor/patch) based on commit types
- Updating version files automatically
- Generating formatted changelog entries
- Running through GitHub Actions CI/CD pipeline

## Project Structure

### Core Implementation
- **version-bumper.js** - Main logic for version management
  - `parseVersion()` - Extract version from files
  - `determineVersionBump()` - Analyze commits and determine bump type
  - `calculateNextVersion()` - Compute new semantic version
  - `updateVersion()` - Write new version to file
  - `generateChangelogEntry()` - Create formatted changelog
  - `runVersionBumper()` - Orchestrate the full workflow

- **bump-version.js** - CLI script for running the version bumper
  - Accepts version file and git ref range as arguments
  - Reads git commit history
  - Updates version and outputs changelog

### Testing
- **version-bumper.test.js** - 20 comprehensive unit tests using Jest
  - Tests for version parsing (3 tests)
  - Tests for bump determination (5 tests)
  - Tests for version calculation (4 tests)
  - Tests for version updating (3 tests)
  - Tests for changelog generation (3 tests)
  - Integration tests (2 tests)

- **test-fixtures.js** - 6 test scenarios for different version bump scenarios
  - Patch bump (fixes only)
  - Minor bump (features)
  - Major bump (breaking changes)
  - No commits (version stays same)
  - Mixed commits (features + fixes + chores)
  - Complex scenario (all types combined)

- **test-workflow.js** - Integration test runner
  - Sets up git repos with test fixtures
  - Runs GitHub Actions workflow via `act`
  - Validates outputs and version bumps
  - Generates `act-result.txt` with results

### GitHub Actions
- **.github/workflows/semantic-version-bumper.yml** - CI/CD Pipeline
  - Two jobs: bump-version and workflow-validation
  - Checkout code, setup Node.js, install dependencies
  - Run Jest tests
  - Execute version bumper script
  - Validate workflow structure and actionlint compliance

## Conventional Commits Specification

The implementation follows [Conventional Commits](https://www.conventionalcommits.org/):

| Commit Type | Bump Type | Example |
|------------|-----------|---------|
| `feat:` | Minor | `feat: added user authentication` |
| `fix:` | Patch | `fix: corrected validation logic` |
| `BREAKING CHANGE:` | Major | `BREAKING CHANGE: removed v1 API endpoints` |
| `chore:`, `docs:`, etc. | Ignored | Not included in changelog |

## Semantic Versioning

Follows [Semantic Versioning 2.0.0](https://semver.org/):

```
MAJOR.MINOR.PATCH
^      ^      ^
|      |      └─ Patch: bug fixes (0.0.1)
|      └────────── Minor: new features (0.1.0)
└───────────────── Major: breaking changes (1.0.0)
```

## Running Tests

### Unit Tests (Local)
```bash
npm test
```

Runs 20 Jest tests covering all core functionality. All tests pass.

### Integration Tests (via act)
```bash
node test-workflow.js
```

Runs GitHub Actions workflow through Docker container using `act`:
- Sets up 6 different test scenarios
- Executes workflow for each scenario
- Validates version bumps and changelog generation
- Outputs results to `act-result.txt`

## Using the CLI

### Basic Usage
```bash
node bump-version.js [version-file] [git-ref-range]
```

### Examples
```bash
# Bump version in package.json based on commits from HEAD~10 to HEAD
node bump-version.js package.json HEAD~10..HEAD

# Bump version in VERSION file
node bump-version.js VERSION HEAD~5..HEAD

# Default: package.json, HEAD~10..HEAD
node bump-version.js
```

### Output
The CLI outputs:
- Current version
- Number of commits found
- Detected bump type
- New version
- Formatted changelog entry
- Updates the version file

## TDD Approach

This project was built using Test-Driven Development:

1. **Red** - Write failing tests first
2. **Green** - Write minimal code to make tests pass
3. **Refactor** - Clean up and improve implementation

Process for each feature:
1. Add test cases to version-bumper.test.js
2. Run tests (they fail)
3. Implement minimal code in version-bumper.js
4. Run tests (they pass)
5. Refactor if needed

## Workflow Validation

The GitHub Actions workflow passes validation:
- ✅ Valid YAML syntax
- ✅ Correct action references (v4 versions)
- ✅ Passes `actionlint` validation
- ✅ Works with `act` local testing
- ✅ Proper permissions and environment setup

To validate locally:
```bash
actionlint .github/workflows/semantic-version-bumper.yml
```

## Test Results

### Unit Tests (20/20 passing)
```
Test Suites: 1 passed, 1 total
Tests:       20 passed, 20 total
Snapshots:   0 total
```

### Workflow Integration Tests (6/6 passing)
```
1. patch-bump-fixture:      ✓ PASSED
2. minor-bump-fixture:      ✓ PASSED
3. major-bump-fixture:      ✓ PASSED
4. no-commits-fixture:      ✓ PASSED
5. mixed-commits-fixture:   ✓ PASSED
6. complex-fixture:         ✓ PASSED
```

See `act-result.txt` for full test output including GitHub Actions workflow logs.

## Example: Version Bumping

### Scenario: Adding a new feature

**Initial state:**
- `package.json`: version = `1.0.0`
- Git commits: `feat: added user authentication`

**After running bump-version:**
- `package.json`: version = `1.1.0` (minor bump)
- Changelog entry generated with feature details

### Scenario: Breaking changes

**Initial state:**
- `package.json`: version = `2.1.3`
- Git commits: `feat: redesigned API\n\nBREAKING CHANGE: removed v1 endpoints`

**After running bump-version:**
- `package.json`: version = `3.0.0` (major bump)
- Changelog marks breaking changes

## Error Handling

The implementation includes graceful error handling for:
- Missing version files
- Invalid JSON in package.json
- Git command failures (returns empty commit list)
- Unknown bump types
- File write errors

All errors produce meaningful error messages to aid debugging.

## Dependencies

- **jest** - Testing framework
- **Node.js fs, path, child_process** - Built-in modules

## Files Included

```
.
├── version-bumper.js                          # Core logic (135 lines)
├── version-bumper.test.js                     # Unit tests (172 lines)
├── bump-version.js                            # CLI script (76 lines)
├── test-fixtures.js                           # Test fixtures (154 lines)
├── test-workflow.js                           # Integration test runner (248 lines)
├── package.json                               # Project config
├── .github/workflows/
│   └── semantic-version-bumper.yml            # GitHub Actions workflow
├── act-result.txt                             # Test results (52KB)
└── README.md                                  # This file
```

## Notes

- All code is well-commented explaining the TDD approach
- Tests use temporary directories for isolation
- Git repos are set up fresh for each test fixture
- Workflow runs in isolated Docker containers via act
- No external dependencies or API calls required
- Graceful handling of edge cases (no commits, no version file, etc.)
