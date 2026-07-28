# Semantic Version Bumper

A Bash-based semantic version bumper that determines the next version based on conventional commit messages following the [Conventional Commits](https://www.conventionalcommits.org/) specification.

## Features

- **Semantic Versioning**: Follows MAJOR.MINOR.PATCH versioning scheme
- **Conventional Commits Analysis**: Automatically detects version bump type from git history
- **Multiple File Format Support**: Works with `package.json` and plain `VERSION` files
- **Changelog Generation**: Extracts commit messages for changelog entries
- **Error Handling**: Graceful error handling with meaningful error messages
- **Shell Best Practices**: Uses `#!/usr/bin/env bash`, passes `shellcheck`, and validates syntax with `bash -n`

## Versioning Rules

The script determines version bumps based on commit types:

- **Breaking Changes** (`feat!:`, `fix!:`, or `BREAKING CHANGE`): Major version bump (1.0.0 → 2.0.0)
- **Features** (`feat:`): Minor version bump (1.0.0 → 1.1.0)
- **Fixes** (`fix:`): Patch version bump (1.0.0 → 1.0.1)
- **No matching commits**: Defaults to patch version bump

## Usage

### Get Current Version

Extract the version from a file:

```bash
./bin/semantic-version-bumper.sh --get-current-version package.json
# Output: 1.2.3

./bin/semantic-version-bumper.sh --get-current-version VERSION
# Output: 1.2.3
```

### Determine Next Version

Calculate the next version based on commits since the last tag:

```bash
./bin/semantic-version-bumper.sh --determine-bump /path/to/repo 1.2.3
# Output: 1.3.0 (if there's a feat commit since the last tag)
```

### Update Version File

Update the version in a file:

```bash
./bin/semantic-version-bumper.sh --update-version package.json 1.3.0
./bin/semantic-version-bumper.sh --update-version VERSION 1.3.0
```

### Generate Changelog

Extract commits since a tag for changelog purposes:

```bash
./bin/semantic-version-bumper.sh --generate-changelog /path/to/repo v1.2.3 1.3.0
```

### Full Workflow

Run the complete version bump workflow in one command:

```bash
./bin/semantic-version-bumper.sh --full-run /path/to/repo VERSION v
# Updates VERSION file and outputs the new version
```

## Testing

### Run Unit Tests

Tests use the [bats-core](https://github.com/bats-core/bats-core) framework:

```bash
bats tests/semantic-version-bumper.bats
```

All 12 tests cover:
1. Parsing versions from package.json
2. Parsing versions from VERSION files
3. Patch version bumping (fix commits)
4. Minor version bumping (feat commits)
5. Major version bumping (breaking changes)
6. Updating package.json
7. Updating VERSION files
8. Changelog generation
9. Full integration with patch bumps
10. Full integration with minor bumps
11. Error handling for invalid versions
12. Error handling for missing files

### Run GitHub Actions Workflow

Test locally with `act`:

```bash
act push --rm
```

This runs both unit tests and integration tests through the CI pipeline.

## Project Structure

```
.
├── README.md                              # This file
├── bin/
│   └── semantic-version-bumper.sh        # Main implementation
├── tests/
│   └── semantic-version-bumper.bats      # Test suite
└── .github/
    └── workflows/
        └── semantic-version-bumper.yml   # GitHub Actions workflow
```

## CI/CD Integration

The GitHub Actions workflow (`.github/workflows/semantic-version-bumper.yml`) includes:

- **Unit Tests Job**: Runs all bats tests, validates with shellcheck and bash -n
- **Integration Tests Job**: Tests real git workflows with version bumping

Both jobs must pass before the workflow succeeds.

## Requirements

- Bash 4.0+
- Git 2.0+
- bats-core (for testing)
- shellcheck (optional, for linting)
- act (optional, for local CI testing)

## Error Handling

The script validates input and provides clear error messages:

- Invalid version format → Error with version format requirement
- Missing files → Error indicating file not found
- Git errors → Handled gracefully with appropriate messages

## Examples

### Example 1: Update VERSION file with detected bump

```bash
#!/bin/bash
REPO="/path/to/git/repo"
VERSION_FILE="VERSION"

# Get current version
CURRENT=$(./bin/semantic-version-bumper.sh --get-current-version "$VERSION_FILE")

# Determine next version
NEXT=$(./bin/semantic-version-bumper.sh --determine-bump "$REPO" "$CURRENT")

# Update the file
./bin/semantic-version-bumper.sh --update-version "$VERSION_FILE" "$NEXT"

echo "Version bumped from $CURRENT to $NEXT"
```

### Example 2: Update package.json before release

```bash
#!/bin/bash
REPO="."
PACKAGE_FILE="package.json"
TAG_PREFIX="v"

# Use full-run for complete workflow
NEW_VERSION=$(./bin/semantic-version-bumper.sh --full-run "$REPO" "$PACKAGE_FILE" "$TAG_PREFIX")

git add package.json
git commit -m "chore: bump version to $NEW_VERSION"
git tag -a "$TAG_PREFIX$NEW_VERSION" -m "Release $NEW_VERSION"
```

## License

MIT
