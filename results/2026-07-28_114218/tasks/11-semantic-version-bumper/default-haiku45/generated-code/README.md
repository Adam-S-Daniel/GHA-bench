# Semantic Version Bumper

A complete TDD implementation of a semantic version bumper that uses conventional commits to determine version increments and generate changelogs.

## Overview

This project implements a semantic version bumper following red/green TDD methodology:

1. **Parse versions** from package.json or VERSION files
2. **Analyze commit messages** using conventional commits (feat, fix, BREAKING CHANGE)
3. **Determine version bump** (major, minor, patch)
4. **Update version files** with new version
5. **Generate changelog entries** from commits
6. **Run through GitHub Actions** pipeline

## Project Structure

```
├── version_bumper.py              # Core library
├── bump_version.py                # CLI tool
├── test_version_bumper.py         # Unit tests (24 tests)
├── test_bump_version_cli.py       # Integration tests (9 tests)
├── fixtures/                      # Mock commit logs
│   ├── commits_minor_bump.txt     # feat + fix commits
│   ├── commits_major_bump.txt     # BREAKING CHANGE commits
│   ├── commits_patch_bump.txt     # only fix commits
│   └── commits_no_bump.txt        # chore/docs only
├── .github/workflows/
│   └── semantic-version-bumper.yml # GitHub Actions workflow
└── act-result.txt                 # Combined test output from act
```

## Features

### version_bumper.py

- **parse_version()**: Read version from package.json or VERSION file
- **determine_bump_type()**: Analyze commit messages for version bump type
- **get_next_version()**: Calculate next semantic version
- **update_version_file()**: Update version in files
- **generate_changelog_entry()**: Create markdown changelog entries

### Supported Commit Types

- `feat:` → Minor version bump (X.1.0)
- `fix:` → Patch version bump (X.0.1)
- `BREAKING CHANGE:` → Major version bump (1.0.0)
- `chore:`, `docs:`, `style:` → No version bump

## Testing

All tests follow red/green TDD methodology:

### Unit Tests (24 tests)
```bash
python3 -m pytest test_version_bumper.py -v
```

Tests cover:
- Version parsing (package.json, VERSION files, leading 'v')
- Conventional commit parsing
- Version bump calculations
- File updates
- Changelog generation
- End-to-end workflows

### Integration Tests (9 tests)
```bash
python3 -m pytest test_bump_version_cli.py -v
```

Tests cover:
- CLI argument parsing
- Error handling
- File I/O
- Fixture loading

### Run All Tests
```bash
python3 -m pytest test_version_bumper.py test_bump_version_cli.py -v
```

**Result: All 33 tests PASS** ✓

## Usage

### Basic Usage

```bash
python3 bump_version.py \
  --version-file package.json \
  --changelog-file CHANGELOG.md \
  --commit-log commits.txt
```

### With Package.json

```bash
python3 bump_version.py \
  --version-file package.json \
  --changelog-file CHANGELOG.md \
  --commit-log commits.txt \
  --verbose
```

Outputs the new version to stdout:
```
1.1.0
```

### Options

- `--version-file`: Path to version file (required)
- `--changelog-file`: Path to changelog file (optional)
- `--commit-log`: Path to file with commit messages (optional)
- `--no-update`: Show result without updating files
- `--verbose`: Print debug information to stderr

## GitHub Actions Workflow

The `.github/workflows/semantic-version-bumper.yml` workflow includes:

### Test Job
- Installs pytest
- Runs all 33 unit and integration tests
- Verifies code quality

### Bump Version Demo Job
- Creates test fixtures (package.json, commits.txt)
- Runs the version bumper
- Verifies version was bumped to 1.1.0
- Verifies changelog was generated with proper formatting

### Workflow Validation Job
- Validates YAML syntax with actionlint
- Checks GitHub Actions best practices

### Workflow Trigger Events
- `push` to main branch
- `pull_request` against main
- `workflow_dispatch` (manual trigger)

## Execution via act

All tests are executed through GitHub Actions using `act`:

```bash
# Run test job (33 tests)
act push --rm -j test

# Run demo job (version bump)
act push --rm -j bump-version

# Run validation job (actionlint)
act push --rm -j workflow-validation
```

### Test Output Summary

From `act-result.txt`:

- **Test Job**: ✅ 24 unit tests PASSED + 9 integration tests PASSED
- **Bump Version Job**: ✅ Version correctly bumped 1.0.0 → 1.1.0
- **Changelog**: ✅ Generated with Features and Fixes sections
- **Workflow Validation**: ✅ YAML syntax valid

## Implementation Details

### TDD Approach

1. **Red**: Write failing tests first
   - Created `test_version_bumper.py` with 24 test cases
   - Tests initially fail (module doesn't exist)

2. **Green**: Implement minimum code to pass
   - Created `version_bumper.py` with core functions
   - All 24 unit tests pass

3. **Refactor**: Add CLI and integration tests
   - Created `bump_version.py` CLI wrapper
   - Added 9 integration tests
   - All tests continue to pass

### Conventional Commits

Implements the conventional commits spec:
- Format: `type(scope): subject`
- Types: feat, fix, chore, docs, style, test, refactor
- Breaking changes: Add `BREAKING CHANGE:` in body or footer

Priority when multiple commit types present:
1. BREAKING CHANGE (major)
2. feat (minor)
3. fix (patch)
4. everything else (no bump)

### Semantic Versioning

Follows SemVer 2.0.0:
- MAJOR version (major.0.0) for incompatible API changes
- MINOR version (X.minor.0) for new functionality
- PATCH version (X.Y.patch) for bug fixes

## Files Created

| File | Purpose |
|------|---------|
| `version_bumper.py` | Core library (6 functions, ~200 LOC) |
| `bump_version.py` | CLI wrapper (~180 LOC) |
| `test_version_bumper.py` | Unit tests (24 tests, ~250 LOC) |
| `test_bump_version_cli.py` | Integration tests (9 tests, ~190 LOC) |
| `.github/workflows/semantic-version-bumper.yml` | GitHub Actions workflow |
| `fixtures/*.txt` | Mock commit log files |
| `act-result.txt` | Combined test output |

## Test Coverage

### Unit Tests Cover

- ✅ Version file parsing (JSON and plain text)
- ✅ Handling 'v' prefix in versions
- ✅ Conventional commit parsing
- ✅ Commit type detection (feat, fix, BREAKING CHANGE, chore)
- ✅ Version bump calculations (major, minor, patch)
- ✅ Invalid version formats
- ✅ File updates (JSON and plain text)
- ✅ Changelog generation with formatting
- ✅ Multiple commit handling
- ✅ Error handling (missing files)

### Integration Tests Cover

- ✅ CLI argument parsing
- ✅ End-to-end workflows
- ✅ File I/O operations
- ✅ Changelog file creation
- ✅ Error messages
- ✅ Test fixtures

## Error Handling

Graceful error handling with meaningful messages:

- **FileNotFoundError**: When version or commit log files don't exist
- **ValueError**: When version format is invalid or unknown commit type
- **JSONDecodeError**: When package.json is malformed
- **Exit code 1**: On errors with stderr message

## Example Usage

### Minor Version Bump (feat commit)

Input files:
- `package.json`: `{"version": "1.0.0"}`
- `commits.txt`: `feat: add user authentication`

Command:
```bash
python3 bump_version.py --version-file package.json --commit-log commits.txt
```

Output:
```
1.1.0
```

### Major Version Bump (breaking change)

Input files:
- `VERSION`: `1.5.3`
- `commits.txt`: `feat: redesign API\n\nBREAKING CHANGE: removed old endpoint`

Command:
```bash
python3 bump_version.py --version-file VERSION --commit-log commits.txt
```

Output:
```
2.0.0
```

## GitHub Actions Integration

The workflow is fully integrated with GitHub Actions:

- ✅ Passes actionlint validation
- ✅ Works with standard ubuntu-latest runner
- ✅ Isolates tests in Docker container (act)
- ✅ No external secrets required
- ✅ Proper error handling and exit codes
- ✅ Detailed step outputs

## Future Enhancements

Possible additions (not implemented per requirements):
- Automated tag creation
- Git log reading (without mocks)
- Pre-release versions (alpha, beta, rc)
- Multiple version file support
- Custom changelog templates
- Dry-run mode with detailed preview

## License

This project was created as part of a benchmarking initiative.
