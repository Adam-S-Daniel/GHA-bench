# Semantic Version Bumper

Automatic semantic versioning based on conventional commits. This tool analyzes git commit messages following the conventional commit specification and automatically determines the next version (major, minor, or patch bump).

## Features

- **Semantic Versioning**: Automatically determines next version based on commit types
- **Conventional Commits**: Analyzes commits following the [Conventional Commits](https://www.conventionalcommits.org/) specification
- **Version File Support**: Works with `package.json` or plain `VERSION` files
- **Changelog Generation**: Automatically generates changelog entries from commits
- **GitHub Actions Integration**: Includes ready-to-use workflow for CI/CD
- **TDD Methodology**: Built using Test-Driven Development with comprehensive test suite

## Quick Start

### Using the Script Directly

```bash
# Parse current version from file
./version-bumper.sh --parse-version package.json

# Determine next version based on commits
./version-bumper.sh --next-version package.json

# Update version in file
./version-bumper.sh --update-version package.json 1.1.0

# Generate changelog from commits
./version-bumper.sh --changelog-from-commits
```

### Using GitHub Actions Workflow

The included workflow automatically runs on push and pull requests:

```yaml
# .github/workflows/semantic-version-bumper.yml
# Triggers on push to main/master
# Outputs:
#   - new_version: The calculated next version
#   - changelog: Auto-generated changelog entries
```

**Manual Workflow Dispatch:**
```bash
gh workflow run semantic-version-bumper.yml \
  -f version_file=package.json \
  -f dry_run=true
```

## Conventional Commits

The tool recognizes conventional commit types:

### Patch Bump (1.0.0 → 1.0.1)
```
fix: correct null pointer exception
perf: optimize database queries
```

### Minor Bump (1.0.0 → 1.1.0)
```
feat: add user authentication
feat: add export to CSV
```

### Major Bump (1.0.0 → 2.0.0)
```
feat!: redesign API interface
BREAKING CHANGE: removed deprecated endpoints
```

## Version File Formats

### JSON (package.json)
```json
{
  "name": "my-app",
  "version": "1.0.0"
}
```

### Text (VERSION)
```
1.0.0
```

## Testing

### Run Unit Tests
```bash
bash test-version-bumper.sh
```

All 7 tests should pass:
- ✓ Parse version from package.json
- ✓ Parse version from VERSION file  
- ✓ Update version in VERSION file
- ✓ Patch bump from fix commit
- ✓ Minor bump from feat commit
- ✓ Major bump from breaking change
- ✓ Generate changelog from commits

### Validate Workflow Structure
```bash
bash test-workflow-structure.sh
```

Tests:
- Workflow file structure
- Script references
- actionlint validation
- Job configuration
- GitHub Actions compatibility

### Test with GitHub Actions (act)
```bash
bash test-with-act.sh
```

Runs the complete workflow in Docker using `act`:
- Creates temporary git repos
- Tests patch/minor/major version bumps
- Verifies workflow outputs
- Validates job execution

### View Test Fixtures
```bash
bash test-fixtures.sh
```

Displays example scenarios and commit patterns.

## How It Works

### TDD Development Process

The implementation was built following Test-Driven Development (TDD):

1. **Red Phase**: Write failing tests first
2. **Green Phase**: Write minimum code to pass tests
3. **Refactor Phase**: Clean up and optimize

### Core Functions

#### `parse_version(file)`
Extracts version from package.json or VERSION file.

```bash
parse_version "package.json"  # → 1.0.0
```

#### `analyze_commits()`
Scans recent git commits for conventional commit patterns.

```bash
analyze_commits  # → "major" | "minor" | "patch"
```

#### `get_next_version(current, bump_type)`
Calculates next semantic version.

```bash
get_next_version "1.0.0" "minor"  # → 1.1.0
get_next_version "1.0.0" "major"  # → 2.0.0
```

#### `update_version(file, new_version)`
Updates version in the specified file.

```bash
update_version "package.json" "1.1.0"
```

#### `generate_changelog()`
Creates changelog entries grouped by type.

```bash
generate_changelog  # Outputs markdown changelog
```

## GitHub Actions Workflow

The workflow (`.github/workflows/semantic-version-bumper.yml`) provides:

### Triggers
- `push` to main/master branches
- `pull_request` against main/master
- Manual `workflow_dispatch`

### Jobs
- **version-bump**: Detects version and generates changelog

### Outputs
- `new_version`: Next version number
- `changelog`: Formatted changelog entries

### Inputs (when manual)
- `version_file`: Path to version file (default: package.json)
- `dry_run`: Preview without making changes (default: true)

## Architecture

```
version-bumper.sh
├── parse_version()          # Extract current version
├── analyze_commits()        # Detect change type
├── get_next_version()       # Calculate new version
├── update_version()         # Write updated version
├── generate_changelog()     # Create changelog
└── main()                   # CLI entry point

test-version-bumper.sh       # Unit tests (7 tests)
test-workflow-structure.sh   # Workflow validation (10 tests)
test-with-act.sh            # Integration tests (3 scenarios)
test-fixtures.sh            # Example test data

.github/workflows/
└── semantic-version-bumper.yml  # GitHub Actions workflow
```

## Error Handling

The script gracefully handles errors:

- Missing version files → Creates default VERSION (1.0.0)
- Invalid git repos → Defaults to patch bump
- Malformed JSON → Uses fallback parsing
- No commits → Assumes patch bump

## Requirements

- bash 4.0+
- git
- jq (optional, for JSON pretty-printing)

For GitHub Actions:
- GitHub Actions runner (Ubuntu latest)
- Docker (for act local testing)

## Test Results

### Unit Tests: 7/7 PASS ✓
```
✓ Parse version from package.json
✓ Parse version from VERSION file
✓ Update version in VERSION file
✓ Patch bump from fix commit
✓ Minor bump from feat commit
✓ Major bump from breaking change
✓ Generate changelog from commits
```

### Workflow Structure Tests: 10/10 PASS ✓
```
✓ Workflow file exists
✓ Script file exists
✓ Script is executable
✓ actionlint validation passes
✓ Workflow has trigger events
✓ Workflow references version-bumper.sh
✓ Workflow has jobs section
✓ Workflow has version-bump job
✓ Workflow uses checkout action
✓ All unit tests pass
```

### Act Integration Tests: 3/3 PASS ✓
```
✓ Patch bump workflow execution (1.0.0 → 1.0.1)
✓ Minor bump workflow execution (2.0.0 → 2.1.0)
✓ Major bump workflow execution (1.5.3 → 2.0.0)
```

## Example Workflow

```bash
# Initial setup
git init my-project && cd my-project
echo '{"name":"app","version":"1.0.0"}' > package.json
git add . && git commit -m "Initial commit"

# Make changes
echo "# New feature" > feature.md
git add . && git commit -m "feat: add awesome feature"

# Check next version
./version-bumper.sh --next-version package.json
# Output: 1.1.0

# Generate changelog
./version-bumper.sh --changelog-from-commits
# Output:
# ### Features
# - add awesome feature

# Update version
./version-bumper.sh --update-version package.json 1.1.0
cat package.json | grep version
# Output: "version": "1.1.0"
```

## Contributing

Tests are in the following files:
- `test-version-bumper.sh` - Unit tests (run first)
- `test-workflow-structure.sh` - Structure validation
- `test-with-act.sh` - Integration with GitHub Actions

All changes must:
1. Pass existing tests
2. Include new tests for new features
3. Follow TDD approach (red-green-refactor)

## License

MIT
