# Semantic Version Bumper

A Bash script that automatically bumps semantic versions based on conventional commit messages, with comprehensive testing and GitHub Actions integration.

## Features

- **Automatic version bumping** based on conventional commits:
  - `feat:` commits trigger a minor version bump
  - `fix:` commits trigger a patch version bump
  - `BREAKING CHANGE:` in commit body triggers a major version bump
- **Support for multiple version file formats**:
  - `package.json` with semantic versioning
  - Plain text `version.txt` files
- **Automatic changelog generation** from commit messages
- **Comprehensive test suite** with bats-core (28 unit tests)
- **GitHub Actions workflow** for CI/CD integration
- **Error handling** with meaningful error messages
- **ShellCheck validated** for portability

## Project Structure

```
.
├── semantic_version_bumper.sh          # Main script
├── test_semantic_version_bumper.bats    # Test suite (28 tests)
├── .github/workflows/
│   └── semantic-version-bumper.yml      # GitHub Actions workflow
├── act-result.txt                       # Test execution log
└── README.md                            # This file
```

## Usage

### Direct Execution

```bash
./semantic_version_bumper.sh <version_file>
```

**Arguments:**
- `version_file`: Path to version file (`package.json` or `version.txt`)

**Output:**
- New version number
- Changelog entry for the new version

**Example:**
```bash
./semantic_version_bumper.sh package.json
# Output:
# 1.1.0
#
# ## [1.1.0] - 2026-07-28
#
# ### Features
# - add user authentication
#
# ### Bug Fixes
# - resolve session timeout
```

### GitHub Actions

The workflow runs automatically on:
- **Push** to `main` or `master` branches
- **Pull requests** to `main` or `master` branches
- **Manual dispatch** (workflow_dispatch)

The workflow:
1. Validates script syntax with `bash -n` and `shellcheck`
2. Runs all 28 unit tests with bats-core
3. Executes integration tests with multiple version bumping scenarios
4. Confirms changelog generation works correctly
5. Reports overall success/failure

## Implementation Details

### Version Parsing

The script parses semantic versions in `MAJOR.MINOR.PATCH` format:

```bash
get_major_version "1.2.3"   # Returns: 1
get_minor_version "1.2.3"   # Returns: 2
get_patch_version "1.2.3"   # Returns: 3
```

### Version Bumping

Based on conventional commits, versions are bumped as follows:

| Commit Type | Bump Type | Example |
|------------|-----------|---------|
| `feat:` | Minor | 1.0.0 → 1.1.0 |
| `fix:` | Patch | 1.0.0 → 1.0.1 |
| `BREAKING CHANGE:` | Major | 1.0.0 → 2.0.0 |

### Version File Updates

**package.json:**
```json
{
  "version": "1.0.0"
}
```

**version.txt:**
```
1.0.0
```

Both formats are automatically detected and updated.

### Changelog Generation

Commits are grouped by type and formatted as:

```markdown
## [1.1.0] - 2026-07-28

### Features
- add user authentication

### Bug Fixes
- resolve session timeout

### Breaking Changes
...
```

## Test Coverage

The project uses **red/green TDD methodology** with 28 comprehensive unit tests:

### Test Categories

1. **Fixture Creation (3 tests)**
   - Creating version files
   - Parsing from package.json
   - Creating mock commit logs

2. **Version Parsing (3 tests)**
   - Extracting major/minor/patch versions
   - Handling different version formats

3. **Bump Logic (6 tests)**
   - Detecting commit types (feat, fix, BREAKING CHANGE)
   - Bumping major/minor/patch versions
   - Handling zero versions

4. **File Updates (2 tests)**
   - Updating package.json
   - Updating version.txt

5. **Changelog Generation (3 tests)**
   - Single commit entries
   - Multiple commit collection
   - Version and date formatting

6. **Integration Tests (3 tests)**
   - Full workflow patch bump
   - Full workflow minor bump
   - Full workflow major bump

7. **Error Handling (3 tests)**
   - Missing files
   - Invalid JSON
   - Missing version fields

8. **History Handling (2 tests)**
   - No tags gracefully
   - Finding commits since last tag

9. **Version File Formats (2 tests)**
   - Detecting package.json format
   - Detecting version.txt format

### Running Tests

```bash
# Run all tests
bats test_semantic_version_bumper.bats

# Run with verbose output
bats test_semantic_version_bumper.bats -v

# Run specific test pattern
bats test_semantic_version_bumper.bats --filter "bump"
```

## GitHub Actions Workflow

The workflow (`.github/workflows/semantic-version-bumper.yml`) includes:

- **Dependencies**: bats-core, shellcheck
- **Validation**: Bash syntax, ShellCheck analysis, actionlint
- **Testing**: 28 unit tests via bats
- **Fixtures**: 5 integration test scenarios
  - Patch bump (fix commits)
  - Minor bump (feat commits)
  - Major bump (BREAKING CHANGE)
  - version.txt format support
  - Changelog generation

### Execution via act

Test the workflow locally using `act`:

```bash
# Run push event
act push --rm

# Run pull_request event
act pull_request --rm

# View results
cat act-result.txt
```

The workflow execution log is saved to `act-result.txt` for review.

## Validation

The solution passes all required validations:

- ✓ **Syntax validation** with `bash -n`
- ✓ **Code analysis** with `shellcheck`
- ✓ **YAML validation** with `actionlint`
- ✓ **28 unit tests** with bats-core
- ✓ **5 integration tests** via GitHub Actions

## Error Handling

The script handles errors gracefully:

```bash
# Missing file
$ ./semantic_version_bumper.sh missing.json
Error: version file 'missing.json' not found

# Invalid JSON
$ ./semantic_version_bumper.sh bad.json
Error: invalid JSON or missing version field in 'bad.json'

# Missing version field
$ ./semantic_version_bumper.sh empty.json
Error: invalid JSON or missing version field in 'empty.json'
```

All errors include meaningful messages to guide users.

## Implementation Approach

The solution follows **test-driven development (TDD)** principles:

1. **Red Phase**: Write failing tests first
2. **Green Phase**: Implement minimal code to pass tests
3. **Refactor Phase**: Improve code quality while maintaining test passing

This ensures:
- High test coverage (28 tests covering all functionality)
- Clear separation of concerns
- Predictable behavior
- Easy maintenance

## Function Reference

### Main Entry Point

- `semantic_version_bumper(version_file)` - Main function that orchestrates the entire process

### Version Parsing

- `get_current_version(file)` - Extract current version from file
- `get_major_version(version)` - Extract major component
- `get_minor_version(version)` - Extract minor component
- `get_patch_version(version)` - Extract patch component

### Version Bumping

- `bump_version(version, bump_type)` - Calculate new version
- `detect_bump_type()` - Determine bump type from commits

### File Operations

- `update_version_in_file(file, version)` - Update version in file
- `get_commits_since_tag(tag)` - Get commits since last tag

### Changelog

- `generate_changelog_entry(new_version)` - Generate formatted changelog

## Requirements

- Bash 4.0+
- Git 2.0+
- `grep`, `sed` standard utilities
- For testing: `bats-core`
- For validation: `shellcheck`, `actionlint`
- For CI/CD: GitHub Actions, Docker (for act)

## License

This solution is provided as-is for the semantic version bumper task.
