# Semantic Version Bumper

A comprehensive bash solution for parsing semantic versions, determining the next version based on conventional commits, updating version files, and generating changelog entries.

## Features

- **Parse semantic versions** from `package.json` or `VERSION` files
- **Analyze git commits** to determine version bump type
- **Apply conventional commit rules**:
  - `feat:` commits → minor version bump
  - `fix:` commits → patch version bump
  - `feat!:` or breaking commits → major version bump
- **Update version files** with new version numbers
- **Generate changelog entries** formatted from commit messages
- **Handle edge cases**: v-prefixed versions, no new commits, invalid formats

## Usage

```bash
./semantic-version-bumper.sh --current-version <file>
./semantic-version-bumper.sh --next-version <file>
./semantic-version-bumper.sh --update <file>
./semantic-version-bumper.sh --changelog <file>
```

### Options

- `--current-version <file>`: Print current version from file
- `--next-version <file>`: Calculate and print next version based on commits
- `--update <file>`: Update version in file to calculated next version
- `--changelog <file>`: Generate changelog entry from recent commits

### Examples

```bash
# Get current version
./semantic-version-bumper.sh --current-version VERSION
# Output: 1.2.3

# Calculate next version
./semantic-version-bumper.sh --next-version VERSION
# Output: 1.3.0 (if feat commits present)

# Update VERSION file
./semantic-version-bumper.sh --update package.json
# Updates "version" field to next version

# Generate changelog
./semantic-version-bumper.sh --changelog VERSION
# Output: Formatted changelog with features, fixes, breaking changes
```

## Testing

### Unit Tests (Local)

Run tests locally with bats:

```bash
bats tests/semantic-version-bumper.bats
```

All 10 tests cover:
1. Parsing version from package.json
2. Parsing version from VERSION file
3. Bumping patch version with fix commits
4. Bumping minor version with feature commits
5. Bumping major version with breaking changes
6. Updating version in package.json
7. Generating changelog entries
8. Handling no new commits
9. Parsing v-prefixed versions
10. Error handling for invalid formats

### Integration Tests (GitHub Actions)

Tests run through GitHub Actions via `act`:

```bash
./test-harness.sh
```

This runs the full workflow including:
- Workflow structure validation
- actionlint validation
- Executing tests through `act` docker container
- Verifying output contains expected values
- Confirming job succeeded

All results are captured in `act-result.txt`.

## Implementation Details

### Red/Green TDD Approach

The implementation follows test-driven development:

1. **Red**: Write failing tests first
2. **Green**: Implement minimum code to make tests pass
3. **Refactor**: Improve code while keeping tests green

### Error Handling

- Validates semantic version format (X.Y.Z)
- Handles missing files with clear error messages
- Gracefully handles malformed JSON
- Exits with error code 1 on validation failures

### Git Integration

- Analyzes `git log` to extract commit messages
- Identifies commit types using conventional commit prefixes
- Handles repos with no git tags
- Processes commits since last version marker

## Files

- `semantic-version-bumper.sh` - Main script (210 lines)
- `tests/semantic-version-bumper.bats` - Test suite (80 lines)
- `test-harness.sh` - Integration test harness for `act`
- `.github/workflows/semantic-version-bumper.yml` - GitHub Actions workflow
- `tests/fixtures/` - Test fixture scripts for complex scenarios

## Requirements

- Bash 4.0+
- Git
- bats-core (for testing)
- act (for GitHub Actions integration testing)
- Docker (for `act` to run workflows)

## GitHub Actions Integration

The workflow (`.github/workflows/semantic-version-bumper.yml`) runs on:
- Push to main/master
- Pull requests
- Manual trigger (workflow_dispatch)
- Weekly schedule (Sunday midnight)

It performs:
1. Script syntax validation with `bash -n`
2. Linting with shellcheck
3. Full test suite execution
4. Test result reporting

## Validation

✅ All 10 unit tests pass locally  
✅ Script passes shellcheck with no warnings  
✅ Script passes bash syntax validation  
✅ Workflow passes actionlint validation  
✅ All 10 tests pass through GitHub Actions via act  
✅ Job succeeded in workflow execution  
✅ act-result.txt created with full output (316 lines)

## Exit Codes

- `0`: Success
- `1`: Validation error, file not found, or version format invalid
- `2`: Missing required arguments

## Performance

- Typical execution: <100ms for local version operations
- Git log analysis: Scales linearly with commit count since last version tag
- No external API calls or network dependencies
