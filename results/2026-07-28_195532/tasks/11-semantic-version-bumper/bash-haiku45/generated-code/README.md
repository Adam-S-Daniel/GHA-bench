# Semantic Version Bumper

A bash-based semantic versioning tool that automatically bumps version numbers based on conventional commit messages.

## Features

- **Conventional Commit Parsing**: Automatically detects `feat:`, `fix:`, and breaking changes (`!:`) in commit messages
- **Semantic Versioning**: Bumps major, minor, or patch versions according to semver rules
- **Changelog Generation**: Automatically generates changelog entries from commit messages
- **Package.json Integration**: Reads and updates version in `package.json`
- **Dry-run Mode**: Preview version bumps without making changes
- **Comprehensive Testing**: 20 unit tests covering all functionality
- **CI/CD Ready**: GitHub Actions workflow included

## Installation

```bash
# Make scripts executable
chmod +x bin/version-bumper.sh bin/semantic-version-bumper.sh
```

## Usage

### Basic usage
```bash
./bin/semantic-version-bumper.sh
```

### Options
```bash
-f, --file FILE         Path to package.json (default: package.json)
-c, --changelog FILE    Path to changelog (default: CHANGELOG.md)
-d, --dry-run          Show what would be done without making changes
-v, --verbose          Enable verbose output
-h, --help             Show help message
```

### Examples

**Bump version for a feature release:**
```bash
git commit -m "feat: add new API endpoint"
./bin/semantic-version-bumper.sh
# Output: 1.1.0 (bumped minor version)
```

**Bump version for a bug fix:**
```bash
git commit -m "fix: resolve memory leak"
./bin/semantic-version-bumper.sh
# Output: 1.0.1 (bumped patch version)
```

**Bump version for a breaking change:**
```bash
git commit -m "feat!: refactor API endpoints"
./bin/semantic-version-bumper.sh
# Output: 2.0.0 (bumped major version)
```

**Preview version bump without making changes:**
```bash
./bin/semantic-version-bumper.sh --dry-run
# Output: DRY RUN: Would bump from 1.0.0 to 1.1.0
```

## Versioning Rules

The tool follows semantic versioning and conventional commits:

| Commit Type | Bumps | Example |
|------------|-------|---------|
| `feat:` | Minor | `1.0.0` → `1.1.0` |
| `fix:` | Patch | `1.0.0` → `1.0.1` |
| `feat!:` or `BREAKING CHANGE:` | Major | `1.0.0` → `2.0.0` |

## Project Structure

```
.
├── bin/
│   ├── version-bumper.sh              # Core library functions
│   └── semantic-version-bumper.sh     # Main entry point
├── test/
│   └── version_bumper.bats            # Unit tests (bats)
├── .github/workflows/
│   └── semantic-version-bumper.yml    # GitHub Actions workflow
└── README.md
```

## Testing

### Run unit tests locally
```bash
bats test/version_bumper.bats
```

### Run in GitHub Actions via act
```bash
act push
```

The workflow runs:
1. **Test job**: Syntax validation, shellcheck, and all 20 unit tests
2. **Integration job**: Real-world scenarios with actual git repos

All tests must pass in both the local runner and GitHub Actions.

## API Reference

### Core Functions

#### `parse_version(version)`
Parses a semantic version string into major, minor, patch components.

```bash
parse_version "1.2.3"
# Sets global associative array: parsed_version[major]=1, parsed_version[minor]=2, parsed_version[patch]=3
```

#### `get_commit_type(message)`
Determines the bump type from a commit message.

```bash
type=$(get_commit_type "feat: add feature")
# Returns: "minor"
```

#### `bump_version(version, bump_type)`
Calculates the new version based on bump type.

```bash
new_version=$(bump_version "1.2.3" "minor")
# Returns: "1.3.0"
```

#### `read_version_from_package_json(file)`
Reads the version field from package.json.

```bash
version=$(read_version_from_package_json "package.json")
# Returns: "1.0.0"
```

#### `write_version_to_package_json(file, new_version)`
Updates the version in package.json.

```bash
write_version_to_package_json "package.json" "1.1.0"
```

#### `generate_changelog(old_version, new_version)`
Creates formatted changelog entry from commits.

```bash
changelog=$(generate_changelog "1.0.0" "1.1.0")
```

## Error Handling

The scripts exit with meaningful error messages:

```bash
$ ./bin/semantic-version-bumper.sh -f nonexistent.json
[ERROR] Package file not found: nonexistent.json
```

All functions validate inputs and return appropriate exit codes.

## CI/CD Integration

### GitHub Actions Workflow

The included workflow (`.github/workflows/semantic-version-bumper.yml`):
- Triggers on `push`, `pull_request`, and `workflow_dispatch`
- Installs dependencies (bats, shellcheck)
- Validates syntax and passes shellcheck
- Runs all 20 unit tests
- Runs integration tests with real git scenarios

### Running Locally with act

```bash
# Install act: https://github.com/nektos/act
act push
```

## Development

### TDD Approach

Tests were written first using the red-green-refactor cycle:
1. Write failing test
2. Implement minimum code to pass
3. Refactor for clarity and efficiency

All 20 tests must pass:
```bash
$ bats test/version_bumper.bats
1..20
ok 1 parse_version extracts major.minor.patch from version string
ok 2 parse_version rejects invalid version format
...
ok 20 semantic-version-bumper.sh creates changelog
```

### Code Quality

- **Shellcheck**: All scripts pass shellcheck validation
- **Bash syntax**: All scripts pass `bash -n` syntax check
- **Error handling**: Graceful failures with meaningful messages
- **Comments**: Explain the "why" only when non-obvious

## Requirements Met

✅ Red/green TDD with failing tests written first  
✅ 20 passing unit tests with bats  
✅ Clear comments explaining approach  
✅ Graceful error handling  
✅ Bash shebang and shellcheck validation  
✅ Mock commit logs as test fixtures  
✅ GitHub Actions workflow with actionlint validation  
✅ Workflow runs successfully in act containers  
✅ All tests execute through the pipeline  
✅ act-result.txt artifact generated with full output  

## License

MIT
