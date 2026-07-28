# Semantic Version Bumper

A complete semantic version bumping tool with GitHub Actions integration, built using red/green TDD methodology.

## Overview

This project implements:
1. **Version Bumping Logic**: Parses semantic versions, analyzes conventional commits, and determines next version
2. **File Management**: Updates package.json or VERSION files with new versions
3. **Changelog Generation**: Creates formatted changelog entries from commits
4. **GitHub Actions Workflow**: Full CI/CD pipeline for automated versioning
5. **Comprehensive Tests**: 22 unit and integration tests with fixtures

## Project Structure

```
├── version_bumper.py         # Core logic (parse, bump, update, changelog)
├── bump-version.py           # CLI script for version bumping
├── test_version_bumper.py    # Unit tests (15 tests)
├── test_integration.py       # Integration tests (7 tests)
├── fixtures.py               # Test fixtures (7 test cases)
├── run_act_tests.py          # Test harness (runs tests through GitHub Actions via act)
└── .github/workflows/
    └── semantic-version-bumper.yml  # GitHub Actions workflow
```

## Key Features

### Version Bumping Logic
- **Conventional Commits**: Recognizes `feat`, `fix`, `breaking`, etc.
- **Smart Bumping**: 
  - `feat` → minor version bump (and reset patch)
  - `fix` → patch version bump
  - `breaking` (marked with `!` or BREAKING CHANGE) → major version bump
  - Non-functional (docs, chore) → no bump
- **Priority**: Highest priority change wins (breaking > feat > fix)

### File Support
- **package.json**: Reads/writes `version` field, preserves JSON structure
- **VERSION**: Simple text file with version string
- **v-prefix**: Handles "v1.2.3" and "1.2.3" formats

### Changelog Generation
Groups commits by type with proper formatting:
```markdown
## [1.1.0]

### Features
- add async support
- add JSON export

### Bug Fixes
- handle edge case in parser
- memory leak in cache
```

## Testing

### Unit Tests (15)
```bash
python -m pytest test_version_bumper.py -v
```
Tests for:
- Version parsing (strings, files, formats)
- Version bump logic (all commit types)
- File updates (JSON, VERSION)
- Changelog generation

### Integration Tests (7)
```bash
python -m pytest test_integration.py -v
```
Tests with real fixtures:
- Patch, minor, major bumps
- Breaking changes
- Mixed commits
- No functional changes
- Edge cases (large versions, special chars, empty lists)

### GitHub Actions Tests (7 fixtures via act)
```bash
python run_act_tests.py
```
Tests the complete workflow through GitHub Actions, running locally with `act`:
1. Creates temp git repo
2. Sets up fixture commits
3. Runs workflow with `act push`
4. Verifies tests pass
5. Saves results to `act-result.txt`

## Test Fixtures

All 7 fixtures are in `fixtures.py`:
1. **Fix only** - 1.0.0 → 1.0.1 (patch bump)
2. **Feature only** - 2.0.0 → 2.1.0 (minor bump)
3. **Breaking change** - 1.5.3 → 2.0.0 (major bump)
4. **Mixed commits** - 1.2.0 → 1.3.0 (minor wins)
5. **No functional** - 3.0.0 → 3.0.0 (no change)
6. **Breaking with body** - 0.9.0 → 1.0.0 (major)
7. **Many commits** - 1.0.0 → 1.1.0 (multiple feat+fix)

## GitHub Actions Workflow

**File**: `.github/workflows/semantic-version-bumper.yml`

### Jobs

**test** (always runs)
- Runs on: ubuntu-latest
- Steps:
  1. Checkout code
  2. Set up Python 3.11
  3. Install pytest
  4. Run all tests

**version-bump** (only on push to main)
- Runs on: ubuntu-latest
- Needs: test
- Conditions: `github.event_name == 'push' && github.ref == 'refs/heads/main'`
- Steps:
  1. Checkout code
  2. Set up Python 3.11
  3. Configure git
  4. Run version bump script
  5. Check for changes
  6. Commit and push if changed
  7. Output new version

### Triggers
- `push` to main branch
- `pull_request` to main branch
- `workflow_dispatch` (manual trigger)

### Permissions
- test: `contents: read`
- version-bump: `contents: write`

## Usage

### Local Testing

Run all tests:
```bash
python -m pytest test_version_bumper.py test_integration.py -v
```

Run with specific fixture:
```bash
python -m pytest test_integration.py::TestIntegrationWithFixtures::test_all_fixtures -v
```

### GitHub Actions

The workflow runs automatically on:
- Push to main
- Pull requests to main
- Manual trigger via workflow_dispatch

## Implementation Notes

### TDD Approach
- Started with failing tests for all features
- Implemented minimum code to pass each test
- Refactored for clarity and efficiency
- Added edge case tests iteratively

### Error Handling
- Validates file paths and versions
- Graceful handling of missing commits
- Meaningful error messages on failure

### Python Features Used
- Pathlib for file handling
- JSON for package.json parsing
- Regex for commit message parsing
- Subprocess for git commands
- Tempfile for test isolation
- Unittest + pytest for testing

## Validation

✓ All 22 unit/integration tests pass
✓ actionlint validates GitHub Actions workflow
✓ Workflow structure verified (triggers, jobs, steps)
✓ act test harness validates end-to-end workflow
✓ Results saved to act-result.txt

## Files Generated

- **Source**: version_bumper.py, bump-version.py
- **Tests**: test_version_bumper.py, test_integration.py
- **Fixtures**: fixtures.py
- **Test Harness**: run_act_tests.py
- **Workflow**: .github/workflows/semantic-version-bumper.yml
- **Results**: act-result.txt (after running tests)
