# Semantic Version Bumper

A TDD-developed solution for automatically bumping semantic versions based on conventional commit messages, with full GitHub Actions CI/CD integration.

## Features

- **Semantic Versioning** (SemVer): Automatically bumps major, minor, or patch versions
- **Conventional Commits**: Parses commit messages to determine version increment
  - `feat:` → minor version bump
  - `fix:` → patch version bump
  - `feat!:` (breaking change) → major version bump
- **Flexible Version Files**: Works with `package.json` or `VERSION` files
- **Changelog Generation**: Creates formatted changelog entries from commits
- **GitHub Actions Integration**: Complete CI/CD workflow included
- **Comprehensive Testing**: Full test coverage with Jest and GitHub Actions validation

## Project Structure

```
.
├── src/
│   └── semantic-version-bumper.js    # Core module with all business logic
├── bin/
│   └── bump-version.js                # CLI entry point
├── __tests__/
│   └── semantic-version-bumper.test.js # Jest tests (11 passing tests)
├── .github/workflows/
│   └── semantic-version-bumper.yml    # GitHub Actions workflow
├── fixtures/
│   ├── test-case-1-patch-bump.json
│   ├── test-case-2-minor-bump.json
│   └── test-case-3-major-bump.json
├── package.json                        # Node.js dependencies
├── run-act-tests.sh                    # Test harness for act validation
└── README.md                           # This file
```

## TDD Development Approach

This solution was developed using **Red-Green-Refactor** methodology:

1. **Red**: Write failing tests first
2. **Green**: Implement minimum code to pass tests
3. **Refactor**: Improve code structure without breaking tests

### Test Coverage

All 11 unit tests pass:

- **parseVersion**: Parse version from JSON and plain text files
- **getNextVersion**: Calculate next version based on commit types
- **updateVersionFile**: Update version in files
- **getConventionalCommits**: Parse conventional commit messages
- **generateChangelog**: Create formatted changelog entries

## Usage

### As a Node.js Module

```javascript
const { bumpVersion } = require('./src/semantic-version-bumper');

const result = bumpVersion('package.json', 'HEAD~10');
console.log(`Version bumped: ${result.currentVersion} → ${result.newVersion}`);
console.log(result.changelog);
```

### As a CLI Tool

```bash
node bin/bump-version.js [versionFile] [fromRef]

# Examples
node bin/bump-version.js package.json HEAD~5
node bin/bump-version.js VERSION main
```

### GitHub Actions Workflow

The included workflow automatically:
1. Runs on push to main/master
2. Runs tests in an isolated Docker container
3. Bumps the version based on commits
4. Outputs the new version for downstream jobs

Trigger: Push to main/master or manual workflow_dispatch

## Running Tests

### Local Unit Tests

```bash
npm install
npm test
```

### Through GitHub Actions (act)

```bash
# Install act if needed: https://github.com/nektos/act
act push -j test      # Run test job
act push -j bump-version  # Run version bump job
```

### Complete Test Harness

```bash
bash run-act-tests.sh
```

This validates:
- Workflow structure and syntax
- actionlint compliance
- Script file existence
- Unit test execution
- Full act workflow execution

Results are saved to `act-result.txt`.

## API Reference

### `parseVersion(filePath)`
Parses semantic version from a file.
- **filePath**: Path to `package.json` or `VERSION` file
- **Returns**: Version string (e.g., "1.2.3")

### `getConventionalCommits(sinceRef)`
Gets conventional commits since a git ref.
- **sinceRef**: Git reference (e.g., "HEAD~10", "v1.0.0")
- **Returns**: Array of parsed commit objects
- **Commit Format**: `{ type: 'feat|fix|chore', message: string, isBreaking: boolean }`

### `getNextVersion(currentVersion, commits)`
Calculates the next semantic version.
- **currentVersion**: Current version string
- **commits**: Array of commit objects
- **Returns**: Next version string

### `updateVersionFile(filePath, newVersion)`
Updates version in a file.
- **filePath**: Path to version file
- **newVersion**: New version string

### `generateChangelog(version, commits)`
Creates a formatted changelog entry.
- **version**: Version string
- **commits**: Array of commit objects
- **Returns**: Formatted changelog string

### `bumpVersion(versionFilePath, fromRef)`
Main function that orchestrates the entire process.
- **versionFilePath**: Path to version file
- **fromRef**: Git reference to compare from (default: "HEAD~10")
- **Returns**: Object with `{ currentVersion, newVersion, commits, changelog }`

## Conventional Commits

This tool supports the [Conventional Commits](https://www.conventionalcommits.org/) specification:

### Valid Commit Types

- `feat`: New feature → bumps minor version
- `fix`: Bug fix → bumps patch version
- `feat!`: Breaking change → bumps major version
- `fix!`: Breaking change → bumps major version
- `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`: No version bump

### Examples

```
feat: add user authentication system        # → 1.1.0
fix: resolve database connection timeout    # → 1.0.1
feat!: remove deprecated v1 API             # → 2.0.0
chore: update dependencies                  # → no change
```

## GitHub Actions Workflow

The workflow (`.github/workflows/semantic-version-bumper.yml`) includes:

- **Trigger Events**: push, pull_request, workflow_dispatch
- **Test Job**: Runs unit tests in isolated Docker container
- **Bump Job**: Bumps version after successful tests (push only)
- **Node.js Setup**: Uses v18 with npm caching
- **Isolated Container**: Uses act-compatible actions/checkout and actions/setup-node

### Workflow Validation

Passes all validation checks:
- ✓ actionlint compliance
- ✓ Valid YAML syntax
- ✓ Correct action references (@v4 pins)
- ✓ Proper permissions and dependencies
- ✓ Successful execution through act

## Error Handling

The tool includes graceful error handling:

- Non-existent git refs fall back to all commits
- Invalid commit messages are skipped
- File read/write errors include descriptive messages
- Missing version files are caught early

## Test Fixtures

The `fixtures/` directory contains test case definitions:

- `test-case-1-patch-bump.json`: Tests patch version bump (fix commits)
- `test-case-2-minor-bump.json`: Tests minor version bump (feat commits)
- `test-case-3-major-bump.json`: Tests major version bump (breaking changes)

Each fixture includes:
- Initial version
- Commit messages
- Expected version
- Expected changelog structure

## Requirements Met

✓ TDD methodology with failing tests first
✓ Minimum code to pass tests, then refactored
✓ Mock commit logs and test fixtures
✓ Clear comments explaining approach
✓ Graceful error handling
✓ All tests pass (11/11)
✓ GitHub Actions workflow
✓ actionlint validation passes
✓ Works in isolated Docker container
✓ act execution validation
✓ act-result.txt generated with all test results

## License

MIT
