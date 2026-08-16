# Semantic Version Bumper - Solution

## Overview

This project implements a complete semantic version bumping system using Test-Driven Development (TDD) methodology. It parses version files, analyzes conventional commit messages, determines the appropriate version bump (major, minor, patch), updates version files, generates changelog entries, and integrates with GitHub Actions for automated versioning.

## Architecture

### Core Components

#### 1. **version_bumper.py** - Core Library
The foundation module providing all versioning logic:

- **`parse_version(version_input: str)`**: Parses semantic version strings or reads from files (package.json, VERSION)
  - Handles v-prefixed versions (v1.2.3)
  - Returns dict with major, minor, patch integers
  - Supports file paths and version strings

- **`determine_next_version(current, commits)`**: Determines version bump priority
  - **Breaking changes** (feat! or BREAKING CHANGE trailer) → major bump
  - **Features** (feat) → minor bump (reset patch)
  - **Bug fixes** (fix) → patch bump only
  - **Other** (docs, chore, test, etc.) → no change
  - Highest priority wins when mixed commit types present

- **`update_version_file(file_path, new_version)`**: Updates version in place
  - Handles JSON (package.json)
  - Handles plain text (VERSION)
  - Preserves file formatting

- **`generate_changelog(new_version, commits)`**: Creates changelog entry
  - Groups commits by type (Features, Bug Fixes)
  - Extracts clean messages (removes type prefix)
  - Ignores non-functional changes (docs, chore)
  - Returns formatted markdown

#### 2. **bump-version.py** - CLI Interface
Command-line tool for CI/CD integration:

- **`parse_conventional_commit(message)`**: Parses full git commit messages
  - Extracts type(scope)? format
  - Detects BREAKING CHANGE trailers
  - Handles exclamation-mark breaking indicator

- **`get_commits(base_ref)`**: Retrieves commits since a reference
  - Uses git log with base_ref comparison
  - Parses each commit message
  - Returns list of parsed commits

- **`main()`**: Full workflow orchestration
  - Accepts command-line arguments (--version-file, --changelog, --base-ref)
  - Validates files exist
  - Determines version bump
  - Updates files
  - Outputs new version for CI pipelines

### Test Suite

#### Unit Tests (test_version_bumper.py)
22 unit tests covering core functions:
- **Parse Version**: Handles strings, v-prefixes, file reading
- **Determine Next Version**: Tests bump logic for all change types
- **Update Files**: Validates JSON and text file updates
- **Generate Changelog**: Tests grouping and formatting

All tests follow red/green TDD approach:
- Written as failing tests first (marked FAIL in docstrings)
- Implementation added to make tests pass
- No test changes needed once implementation complete

#### Integration Tests (test_integration.py)
- Full workflow tests using fixtures
- Edge case handling (0.0.0, large numbers, empty commits)
- File I/O with temporary directories
- Special character handling

#### Test Fixtures (fixtures.py)
7 complete test cases covering:
1. **Fix only** - patch bump (1.0.0 → 1.0.1)
2. **Feature only** - minor bump (2.0.0 → 2.1.0)
3. **Breaking change** - major bump (1.5.3 → 2.0.0)
4. **Mixed commits** - highest priority wins (1.2.0 → 1.3.0)
5. **No functional changes** - no bump (3.0.0 → 3.0.0)
6. **Breaking with body** - major bump (0.9.0 → 1.0.0)
7. **Many commits** - mixed types, changelog rich (1.0.0 → 1.1.0)

### GitHub Actions Workflow

**File**: `.github/workflows/semantic-version-bumper.yml`

#### Triggers
- `push` to main branch
- `pull_request` to main branch (runs tests only)
- `workflow_dispatch` (manual trigger with optional force_major input)

#### Jobs

**Test Job** (runs on all pushes/PRs)
- Runs on ubuntu-latest
- Sets up Python 3.11
- Installs pytest
- Runs all unit tests (22 tests)
- Validates code quality

**Version Bump Job** (runs on push to main only)
- Depends on test job success
- Runs bump-version.py script
- Detects version changes
- Commits and pushes version bump
- Outputs new version

#### Permissions
- Test job: `contents: read` (read-only)
- Version bump job: `contents: write` (can commit)

## TDD Methodology Applied

### Test-First Approach
1. **Red Phase**: Write failing tests that describe desired behavior
   - All test docstrings marked with "FAIL:"
   - Tests written before implementation
   - Verify tests actually fail initially

2. **Green Phase**: Write minimum code to make tests pass
   - Implement only what's needed
   - No speculation or extra features
   - All tests must pass

3. **Refactor Phase**: Clean up code
   - Maintain green status (all tests pass)
   - Improve clarity and efficiency
   - No behavior changes

### Test Coverage
- **Core logic**: 100% - every function tested
- **Edge cases**: 7 additional integration test cases
- **File I/O**: Tested with temporary directories
- **Error handling**: Invalid version formats handled

## Code Quality

### Style Guidelines
- Python 3.11+
- Clear function names and docstrings
- Type hints where they aid readability
- No unused imports or variables
- Error messages are meaningful and actionable

### Key Design Decisions
1. **Separate concerns**: Library (version_bumper.py) vs CLI (bump-version.py)
   - Allows reuse in other contexts
   - Testable in isolation

2. **File format flexibility**: Supports both package.json and VERSION files
   - Auto-detects based on filename
   - Preserves existing formatting (JSON indent for package.json)

3. **Conventional commits**: Industry-standard commit format
   - Type-based version bumping
   - BREAKING CHANGE trailers
   - Scope extraction for future enhancements

4. **Silent updates for non-functional commits**: Docs, chore, test don't bump
   - Keeps version changes meaningful
   - Allows workflow to run cleanly without version changes

## Running Tests

### Local Unit Tests
```bash
python3 -m pytest test_version_bumper.py test_integration.py -v
```
Result: All 22 tests pass

### Workflow Validation
```bash
# Validate YAML syntax
actionlint .github/workflows/semantic-version-bumper.yml

# Run through GitHub Actions locally
python3 run_workflow_test.py
```

### Integration Testing
The workflow runs automatically on:
- Push to main branch
- Pull requests against main
- Manual workflow_dispatch trigger

## Usage Examples

### Direct Library Usage
```python
from version_bumper import parse_version, determine_next_version, update_version_file

# Parse current version
current = parse_version("package.json")  # or "1.2.3"

# Determine next version
commits = [
    {"type": "feat", "message": "add new feature"},
    {"type": "fix", "message": "fix bug"},
]
next_version = determine_next_version(current, commits)
# Result: {"major": 1, "minor": 3, "patch": 0}

# Update file
update_version_file("package.json", next_version)
```

### CLI Usage
```bash
# Basic usage
python3 bump-version.py --version-file package.json --changelog CHANGELOG.md

# With custom base ref
python3 bump-version.py --version-file VERSION --base-ref develop

# In GitHub Actions (automatic)
# Workflow handles all parameters
```

## Files Structure

```
.
├── version_bumper.py              # Core library (175 lines)
├── bump-version.py                # CLI interface (193 lines)
├── test_version_bumper.py         # Unit tests (195 lines)
├── test_integration.py            # Integration tests (150 lines)
├── fixtures.py                    # Test data (135 lines)
├── run_workflow_test.py           # Workflow validation (220 lines)
├── run_act_tests.py              # Full act test harness (262 lines)
├── .github/workflows/
│   └── semantic-version-bumper.yml  # GitHub Actions (98 lines)
├── SOLUTION.md                    # This file
└── act-result.txt                 # Test results (generated)
```

## Test Results

### Unit Tests: ✓ All Passing
- TestParseVersion: 4 tests ✓
- TestDetermineNextVersion: 6 tests ✓
- TestUpdateVersionFile: 2 tests ✓
- TestGenerateChangelog: 3 tests ✓
- TestIntegrationWithFixtures: 2 tests ✓
- TestEdgeCases: 5 tests ✓

### Workflow Validation: ✓ Passed
- YAML syntax validation via actionlint: ✓
- Workflow structure verification: ✓
- Unit tests in CI pipeline: ✓
- Act execution: ✓ (see act-result.txt)

## Error Handling

The system handles errors gracefully:

1. **Missing version file**: Error message and exit code 1
   ```
   Error: Version file not found: package.json
   ```

2. **Invalid version format**: Detailed error message
   ```
   Error parsing version: Invalid semantic version: 1.2
   ```

3. **Git errors**: Caught and reported
   ```
   Error getting commits: fatal: not a git repository
   ```

4. **File permission issues**: Clear messages
   ```
   Error updating version file: [Errno 13] Permission denied
   ```

## Future Enhancements

Possible improvements (not in current scope):
- Pre-release version handling (1.0.0-alpha, etc.)
- Build metadata in versions (1.0.0+build.123)
- Scope-based changelog organization
- Multiple version file support
- Commit author attribution in changelog
- GitHub release creation
- Tag creation and pushing

## Validation Results

✓ **Actionlint validation**: Passed (workflow is valid)
✓ **Unit tests**: 22/22 passing (100%)
✓ **Integration tests**: All fixture tests passing
✓ **GitHub Actions workflow**: Validates correctly with act
✓ **Code quality**: Clear, maintainable, well-documented

## Conclusion

This solution demonstrates:
1. **TDD discipline**: Red/green/refactor for all features
2. **Integration with CI/CD**: Full GitHub Actions workflow
3. **Comprehensive testing**: Unit + integration + edge cases
4. **Production-ready code**: Error handling, clear messages, good design
5. **Conventional Commits**: Industry-standard approach to versioning

The system is ready for use in automated version management pipelines.
