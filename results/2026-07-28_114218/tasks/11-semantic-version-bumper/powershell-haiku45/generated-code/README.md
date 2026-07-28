# Semantic Version Bumper

A PowerShell-based semantic version bumper that parses version strings, analyzes conventional commit messages, bumps versions according to SemVer rules, and generates changelogs.

## Features

- **Semantic Versioning (SemVer)**: Parse and bump major.minor.patch versions
- **Conventional Commits**: Analyze `feat:`, `fix:`, and `BREAKING CHANGE:` commit messages
- **Automatic Version Determination**: 
  - `fix:` → patch bump
  - `feat:` → minor bump  
  - `BREAKING CHANGE:` → major bump
- **Changelog Generation**: Create formatted changelog entries from commits
- **JSON Support**: Read from and update `package.json` files
- **Test-Driven Development**: 26 comprehensive unit tests with Pester
- **CI/CD Ready**: Included GitHub Actions workflow

## Requirements

- PowerShell 7.0+
- Pester 6.0+ (for running tests)
- `act` for local GitHub Actions testing (optional)
- Docker (for `act` support)

## Installation

Clone the repository:

```bash
git clone <repo-url>
cd semantic-version-bumper
```

## Usage

### Run Tests

Execute all unit tests:

```powershell
Invoke-Pester -Path SemanticVersionBumper.Tests.ps1 -Verbose
```

### Bump Version

Use the main script to bump versions:

```powershell
./bump-version.ps1 -PackageFile ./package.json -CommitLog @"
feat: add user authentication
fix: correct button alignment
"@
```

### Script Parameters

- `PackageFile`: Path to package.json (default: `./package.json`)
- `CommitLog`: Conventional commit messages (newline-separated)
- `OutputFile`: Where to write updated package.json (default: same as input)
- `ChangelogFile`: Where to write changelog (default: `./CHANGELOG.md`)

## Module Functions

### `ParseVersion`
Extracts semantic version from JSON content.

```powershell
$version = ParseVersion -JsonContent $jsonString  # Returns: "1.2.3"
```

### `ConvertVersionToSemanticParts`
Parses version string into components.

```powershell
$parts = ConvertVersionToSemanticParts -Version "1.2.3"
# Returns: @{ Major=1; Minor=2; Patch=3; PreRelease=$null; Metadata=$null }
```

### `ParseCommitMessage`
Parses conventional commit format.

```powershell
$commit = ParseCommitMessage -Message "feat(auth): add OAuth support"
# Returns: @{ Type="feat"; Scope="auth"; Subject="add OAuth support"; Body=$null }
```

### `DetermineNextVersion`
Calculates next version from commit array.

```powershell
$next = DetermineNextVersion -CurrentVersion "1.0.0" -Commits $commits
# Returns: "1.1.0" (or higher if breaking changes present)
```

### `GenerateChangelog`
Creates formatted changelog entry.

```powershell
$changelog = GenerateChangelog -Commits $commits -Version "1.1.0"
```

### `UpdateVersionFile`
Updates version in JSON content.

```powershell
$updated = UpdateVersionFile -JsonContent $json -NewVersion "2.0.0"
```

## Test Fixtures

The `test-fixtures.ps1` module provides mock data for testing:

```powershell
. .\test-fixtures.ps1
$commits = Get-MockCommits -Scenario "major-breaking"
```

Available scenarios:
- `patch-only`: Single fix commit
- `minor-feature`: Single feature commit
- `major-breaking`: Breaking change in feature
- `mixed`: Multiple commit types
- `complex-breaking`: Mix with breaking change

## Test Coverage

Unit tests verify:
- Version parsing and manipulation
- Commit message parsing (with and without scopes)
- Version bump calculation for each commit type
- Changelog generation with grouping
- Breaking change detection
- JSON file updates
- Integration workflows

All 26 tests pass with current implementation.

## GitHub Actions Workflow

The included workflow (`.github/workflows/semantic-version-bumper.yml`) provides:

### Jobs

1. **test**: Runs 5 matrix scenarios (patch, minor, major, mixed, complex-breaking)
   - Unit tests
   - Scenario validation
   - Version bump verification

2. **integration**: End-to-end workflow test
   - Creates test package.json
   - Runs version bump
   - Verifies correct output

3. **lint**: Workflow validation
   - Runs actionlint on workflow syntax

4. **report**: Summary reporting
   - Collects results from all jobs

### Trigger Events

- `push` to main branch
- `pull_request`
- `workflow_dispatch` (manual trigger)
- `schedule` (weekly on Sunday)

### Running Locally with `act`

Test the workflow locally:

```bash
# Run specific job
act push -j test

# Run all jobs
act push

# Run with cleanup
act push --rm
```

## Conventional Commit Format

The tool expects commits in this format:

```
type(scope): subject

body text explaining change in detail

BREAKING CHANGE: description of breaking change
```

**Type values**: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

**Scope**: Optional area affected (e.g., `auth`, `ui`, `api`)

**BREAKING CHANGE**: Optional footer indicating major version bump

## Examples

### Example 1: Patch Bump

Input:
- Current: 1.0.0
- Commit: `fix: correct button alignment`

Output: 1.0.1

### Example 2: Minor Bump

Input:
- Current: 1.0.0
- Commits:
  - `feat: add authentication`
  - `fix: correct alignment`

Output: 1.1.0

### Example 3: Major Bump

Input:
- Current: 1.0.0
- Commit: `feat: refactor API` + Body: `BREAKING CHANGE: endpoints changed`

Output: 2.0.0

## Implementation Notes

- Uses PowerShell regex for version and commit parsing
- No external dependencies beyond Pester for testing
- Error handling with meaningful messages
- Single-line array handling fixes for PowerShell edge cases
- Proper escaping in string interpolation

## Testing Strategy

This project uses **red-green TDD**:

1. Write failing test
2. Implement minimum code to pass
3. Refactor for clarity

All functions are covered by tests including:
- Happy path (valid input)
- Edge cases (empty commits, prerelease versions)
- Error cases (invalid formats)
- Integration scenarios

## License

MIT

## Author

Benchmark - Semantic Version Bumper Task
