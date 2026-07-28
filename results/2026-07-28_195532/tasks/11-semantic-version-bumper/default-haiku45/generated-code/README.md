# Semantic Version Bumper

A tool that automatically bumps semantic versions based on conventional commit messages. Uses test-driven development (TDD) methodology with comprehensive unit and integration tests.

## Features

- ✅ Parse semantic versions from `package.json`
- ✅ Analyze conventional commits (feat, fix, breaking changes)
- ✅ Automatically bump versions (major, minor, patch)
- ✅ Generate changelog entries from commits
- ✅ Update version files
- ✅ Git integration to fetch commits since a tag
- ✅ Comprehensive test suite (17 tests, all passing)
- ✅ GitHub Actions workflow with actionlint validation
- ✅ Successful CI/CD execution via `act`

## Project Structure

```
.
├── semantic_version_bumper.py    # Core logic
├── main.py                       # CLI entry point
├── fixtures.py                   # Test fixtures and mock git repos
├── test_semantic_version_bumper.py  # Unit tests (11 tests)
├── test_integration.py           # Integration tests (6 tests)
├── package.json                  # Sample package configuration
├── .github/workflows/
│   └── semantic-version-bumper.yml  # GitHub Actions workflow
├── act-result.txt               # CI/CD execution output
└── README.md                     # This file
```

## Version Bumping Rules

The tool follows semantic versioning conventions:

| Commit Type | Bump Type | Example |
|------------|-----------|---------|
| `feat:` | Minor | `feat: add new feature` → 1.0.0 → 1.1.0 |
| `fix:` | Patch | `fix: resolve bug` → 1.0.0 → 1.0.1 |
| `feat!:` or `fix!:` | Major | `feat!: breaking change` → 1.0.0 → 2.0.0 |
| `docs:`, `chore:`, etc. | None | No version change |

## Usage

### Basic Usage

```bash
python3 main.py --repo-path . --tag v1.0.0 --package-json package.json
```

### With Dry-Run

See what would change without modifying files:

```bash
python3 main.py --repo-path . --tag v1.0.0 --package-json package.json --dry-run
```

### Options

- `--repo-path`: Path to git repository (default: `.`)
- `--tag`: Git tag to use as base for commit log (default: `v1.0.0`)
- `--package-json`: Path to package.json file (default: `package.json`)
- `--dry-run`: Print changes without writing files

## Running Tests

### All Tests

```bash
python3 -m pytest test_semantic_version_bumper.py test_integration.py -v
```

### Unit Tests Only

```bash
python3 -m pytest test_semantic_version_bumper.py -v
```

### Integration Tests Only

```bash
python3 -m pytest test_integration.py -v
```

### With Coverage

```bash
python3 -m pytest --cov=semantic_version_bumper test_*.py -v
```

## Test Coverage

### Unit Tests (11 tests)
- Version parsing from package.json
- Conventional commit parsing
- Breaking change detection
- Version bumping (major, minor, patch, no-change)
- Package.json update
- Changelog generation
- Git commit extraction

### Integration Tests (6 tests)
- Minor version bump workflow
- Patch version bump workflow
- Major version bump workflow
- Mixed commits with priority handling
- No-bump scenario
- Package.json update verification

## Implementation Approach

The project follows **Test-Driven Development (TDD)**:

1. **Red Phase**: Write failing test for desired functionality
2. **Green Phase**: Write minimal code to make test pass
3. **Refactor Phase**: Improve code quality while keeping tests passing

This ensures high quality, well-tested code with clear specifications.

## GitHub Actions Workflow

The workflow (`.github/workflows/semantic-version-bumper.yml`):

- ✅ Runs on push, pull_request, and manual trigger
- ✅ Checks out code with full git history
- ✅ Installs Python 3.11 and pytest
- ✅ Executes all 17 tests
- ✅ Runs the semantic version bumper tool
- ✅ Captures and reports output
- ✅ Passes `actionlint` validation
- ✅ Successfully executes via `act` (Docker-based testing)

### Running Workflow Locally

```bash
# Validate workflow syntax
actionlint .github/workflows/semantic-version-bumper.yml

# Execute workflow with act
act push --rm
```

## CI/CD Execution Results

The workflow has been successfully tested with `act`:

```
Test Results:
- 17 tests collected
- 17 tests PASSED
- 0 tests FAILED
- Job Status: ✅ succeeded

Output saved to: act-result.txt
```

## Test Fixtures

The `fixtures.py` module provides mock git repositories for testing:

- `FIXTURE_MINOR_BUMP`: Commits that trigger minor version bump
- `FIXTURE_PATCH_BUMP`: Commits that trigger patch version bump
- `FIXTURE_MAJOR_BUMP`: Commits that trigger major version bump (breaking changes)
- `FIXTURE_MIXED_BUMP`: Mix of different commit types
- `FIXTURE_NO_BUMP`: Commits that don't trigger version change

## Error Handling

The tool gracefully handles errors:

- Missing package.json files
- Invalid git repositories
- Missing git tags
- Malformed version strings

Example error message:
```
Error: /path/to/package.json not found
```

## Example Output

```
Current version: 1.0.0
Found 2 commits since v1.0.0
Bump type: minor

Changelog:
## [1.1.0]

### Features
- add new feature

### Bug Fixes
- resolve bug in login

✓ Updated package.json

Bumped version: 1.0.0 → 1.1.0
1.1.0
```

## Design Decisions

1. **Python 3.11+**: Clear, readable syntax for task automation
2. **Standard library only**: No external dependencies for core functionality
3. **Conventional commits**: Industry-standard specification
4. **Git integration**: Real repository analysis, not mock-based
5. **TDD approach**: Ensures reliability and maintainability

## Future Enhancements

- Support for multiple version file formats (pyproject.toml, VERSION file, etc.)
- Git tag creation for released versions
- Automated changelog file updates (CHANGELOG.md)
- NPM publish integration
- Pre-release version handling (alpha, beta, rc)
- Custom bumping rules via configuration file

## License

MIT

## Author

Generated via Test-Driven Development
