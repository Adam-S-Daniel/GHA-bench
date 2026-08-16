# Semantic Version Bumper

A bash-based semantic version bumper that analyzes conventional commit messages to automatically determine and apply semantic version increments.

## Overview

This tool implements a semantic version bumper following the TDD (Test-Driven Development) methodology using bash, bats-core for testing, and GitHub Actions for CI/CD.

### Features

- **Parse versions** from `package.json` or `VERSION` files
- **Analyze commits** using conventional commit format (feat, fix, BREAKING CHANGE)
- **Calculate next version** based on commit analysis
- **Update version files** (package.json or VERSION)
- **Generate changelog** entries from commit messages
- **100% test coverage** with 10 comprehensive unit tests
- **GitHub Actions integration** with proper workflow validation

## Quick Start

### Prerequisites

- bash 4.0+
- git
- bats-core (for testing)
- shellcheck (for script validation)
- actionlint (for workflow validation)
- Docker (for running tests via act)

### Installation

```bash
chmod +x semver-bumper.sh
```

### Basic Usage

```bash
# Parse current version
./semver-bumper.sh parse-version

# Calculate next version based on commits
./semver-bumper.sh calculate-next-version 1.0.0

# Update version in a file
./semver-bumper.sh update-version package.json 1.1.0

# Generate changelog entry
./semver-bumper.sh generate-changelog 1.0.0 1.1.0
```

## Versioning Logic

The tool follows [Semantic Versioning 2.0.0](https://semver.org/):

| Commit Type | Version Bump | Example |
|---|---|---|
| `fix:` | PATCH | 1.0.0 → 1.0.1 |
| `feat:` | MINOR | 1.0.0 → 1.1.0 |
| `BREAKING CHANGE` | MAJOR | 1.0.0 → 2.0.0 |
| Other (docs, etc.) | None | 1.0.0 → 1.0.0 |

### Multiple Commits

When there are multiple commits of the same type, version increments stack:
- 2 fix commits: 1.0.0 → 1.0.2
- 1 feat + 2 fixes: 1.0.0 → 1.1.0 (feat takes precedence)

## Testing

### Run Unit Tests

```bash
bats tests/version_bumper.bats
```

All 10 tests pass:
1. Parse version from package.json
2. Parse version from VERSION file
3. Bump patch for fix commits
4. Bump minor for feat commits
5. Bump major for breaking changes
6. Update VERSION file
7. Update package.json
8. Generate changelog
9. No bump for docs-only changes
10. Multiple commit types

### Run Through GitHub Actions

```bash
# Run complete test suite via act
bash run-act-tests.sh
```

This executes:
1. Workflow structure validation
2. Script reference checks
3. actionlint validation
4. Full act workflow execution
5. Core functionality tests
6. bats unit tests
7. Summary report

Output is saved to `act-result.txt`.

## Code Quality

### Script Validation

```bash
# Syntax check
bash -n semver-bumper.sh

# Linting
shellcheck semver-bumper.sh

# Workflow validation
actionlint .github/workflows/semantic-version-bumper.yml
```

All checks pass cleanly with no warnings.

## GitHub Actions Workflow

The workflow file `.github/workflows/semantic-version-bumper.yml` provides CI/CD integration:

### Triggers
- `push` to main/master branches
- `pull_request`
- `workflow_dispatch` (manual trigger)

### Jobs

1. **test** - Runs unit tests
   - Validates script syntax
   - Runs shellcheck
   - Executes bats tests

2. **demo** - Demonstrates version bumping
   - Creates sample project
   - Adds feature and fix commits
   - Bumps version
   - Updates files
   - Generates changelog

### Permissions

- `contents: read` - Read-only repository access (minimal permissions)

## Architecture

### Script Structure

The script is organized into logical functions:

- `parse_version_string()` - Parse semantic version components
- `parse_version()` - Read version from files
- `analyze_commits()` - Count commit types
- `calculate_next_version()` - Compute new version
- `update_version()` - Write new version to files
- `generate_changelog()` - Create changelog entries
- `main()` - Command dispatcher

### Error Handling

- Graceful error messages on missing files
- Proper exit codes (0 for success, 1 for failure)
- Input validation on all commands

### Git Integration

The tool examines all commits in the git repository:
- Full commit messages (for BREAKING CHANGE detection)
- Commit subjects (for feat/fix type detection)
- Works with any number of commits

## Testing Methodology

This project follows TDD (Test-Driven Development):

1. **Red Phase** - Write failing tests first
2. **Green Phase** - Implement minimum code to pass tests
3. **Refactor Phase** - Improve code quality while maintaining tests

### Test Fixtures

Tests create isolated temporary git repositories with:
- Real git commits with conventional commit messages
- Multiple commit types for edge case testing
- Version files (package.json and VERSION)

### Test Isolation

Each test:
- Runs in its own temporary directory
- Has a fresh git repository
- Cleans up after completion
- Cannot affect other tests

## Files

- `semver-bumper.sh` - Main script (180 lines)
- `tests/version_bumper.bats` - Unit tests (165 lines)
- `.github/workflows/semantic-version-bumper.yml` - CI/CD workflow
- `run-act-tests.sh` - Test harness for act execution
- `act-result.txt` - Test execution results

## Requirements Met

✅ Red/Green TDD methodology with failing tests first  
✅ All tests pass (10/10)  
✅ bats-core testing framework  
✅ Meaningful error messages  
✅ `#!/usr/bin/env bash` shebang  
✅ Passes shellcheck validation  
✅ Passes bash -n syntax validation  
✅ GitHub Actions workflow created  
✅ Workflow passes actionlint  
✅ All tests run through act  
✅ act-result.txt generated with test results  

## Example Workflow

```bash
# In a project with git history
$ ./semver-bumper.sh parse-version
1.0.0

$ git log --oneline | head -3
abc1234 fix: handle null pointer
def5678 feat: add authentication
ghi9012 Initial commit

$ ./semver-bumper.sh calculate-next-version 1.0.0
1.1.0

$ ./semver-bumper.sh update-version package.json 1.1.0
$ cat package.json
{"version": "1.1.0", ...}

$ ./semver-bumper.sh generate-changelog 1.0.0 1.1.0
## [1.1.0] - 2026-07-28

### Features
- add authentication

### Bug Fixes
- handle null pointer
```

## License

This project is part of the GHA-bench benchmark suite.
