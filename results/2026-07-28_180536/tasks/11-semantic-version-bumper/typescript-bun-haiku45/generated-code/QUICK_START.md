# Quick Start Guide

## Running Tests

### Run all unit tests
```bash
bun test
```
**Expected**: 41 pass, 0 fail

### Run specific test file
```bash
bun test tests/semver.test.ts
```

### Run with verbose output
```bash
bun test --verbose
```

## Running the Tool

### Basic usage - bump version
```bash
bun run src/index.ts \
  --version-file package.json \
  --previous-tag v1.0.0
```

### Dry run (no changes to files)
```bash
bun run src/index.ts \
  --version-file package.json \
  --previous-tag v1.0.0 \
  --dry-run
```

### With changelog generation
```bash
bun run src/index.ts \
  --version-file package.json \
  --previous-tag v1.0.0 \
  --changelog-file CHANGELOG.md
```

### Using VERSION file instead of package.json
```bash
bun run src/index.ts \
  --version-file VERSION \
  --previous-tag v1.0.0
```

## Validating Workflow

### Validate workflow YAML syntax
```bash
actionlint .github/workflows/semantic-version-bumper.yml
```
**Expected**: No output (validation passed)

### Run complete validation
```bash
bash run-final-validation.sh
```
**Expected**: All validations pass, results in `act-result.txt`

## Testing with ACT (Local GitHub Actions Runner)

### Run workflow locally
```bash
act push -j test
```

### Run only test job
```bash
act push -j test --rm -q
```

### Run version-bump job
```bash
act push -j version-bump --rm -q
```

## Understanding Version Bumping

The tool uses **conventional commits** to determine version bumps:

| Commit Type | Example | Old → New | Reason |
|-------------|---------|-----------|--------|
| fix | `fix: bug` | 1.0.0 → 1.0.1 | Patch release |
| feat | `feat: feature` | 1.0.0 → 1.1.0 | Minor release |
| breaking | `feat!: API change` | 1.0.0 → 2.0.0 | Major release |
| docs | `docs: update README` | 1.0.0 → 1.0.0 | No bump |
| chore | `chore: deps` | 1.0.0 → 1.0.0 | No bump |

### Breaking Changes

Breaking changes can be indicated two ways:

```bash
# Method 1: Using ! after type
git commit -m "feat!: remove deprecated API"

# Method 2: Using BREAKING CHANGE footer
git commit -m "feat: new API

BREAKING CHANGE: old API is no longer supported"
```

Both result in a MAJOR version bump.

## Command Line Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `--version-file` | package.json | Path to version file |
| `--previous-tag` | v1.0.0 | Git tag to compare against |
| `--changelog-file` | CHANGELOG.md | (Optional) File to append changelog to |
| `--dry-run` | false | Preview changes without writing |

## Output Format

The tool outputs the new version in CI-friendly format:

```
Current version: 1.0.0
Found 3 commits since v1.0.0
Version bump type: minor
New version: 1.1.0
✓ Updated package.json to 1.1.0
✓ Updated CHANGELOG.md
::VERSION::1.1.0
```

The `::VERSION::X.Y.Z` line can be parsed by CI systems.

## Troubleshooting

### "Version file not found"
- Check file path with `--version-file`
- Ensure file exists in current directory

### "Invalid version format"
- Check version string is semantic (X.Y.Z)
- Remove any non-numeric characters except dots

### No commits found
- Check `--previous-tag` exists in git
- Verify commits exist since the tag
- Try without tag (tool falls back to all commits)

### Tests fail
Run with verbose output:
```bash
bun test --verbose
```

### Workflow validation fails
Check syntax:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/semantic-version-bumper.yml'))"
```

## Working with the Workflow

The GitHub Actions workflow runs automatically on:
- Push to `main` or `master`
- Pull requests to `main` or `master`
- Manual trigger via workflow_dispatch

### Manual Trigger

Use GitHub UI or CLI:
```bash
gh workflow run semantic-version-bumper.yml \
  -f version_file=package.json \
  -f previous_tag=v1.0.0
```

## Project Structure

```
.
├── src/                         # Source code
│   ├── index.ts                # Main CLI
│   ├── semver.ts               # Version logic
│   ├── commits.ts              # Commit parsing
│   ├── git.ts                  # Git integration
│   ├── files.ts                # File I/O
│   └── changelog.ts            # Changelog generation
├── tests/                        # Tests
│   ├── *.test.ts               # Unit tests
│   └── integration.test.ts      # Integration tests
├── .github/workflows/           # CI/CD
│   └── semantic-version-bumper.yml
├── package.json                # Project metadata
└── tsconfig.json               # TypeScript config
```

## Development Tips

### Adding a new test
1. Create test file in `tests/`
2. Use Bun's test syntax:
```typescript
import { expect, test } from "bun:test";

test("should do something", () => {
  expect(result).toBe(expected);
});
```

### Running specific tests
```bash
bun test tests/semver.test.ts
```

### Debugging commits
```bash
# See commits since tag
git log v1.0.0..HEAD --oneline

# See exact commit messages
git log v1.0.0..HEAD --pretty=format:%B
```

### Testing version bumping locally
```bash
# Create test repo
mkdir test-repo && cd test-repo
git init
git config user.name "Test" && git config user.email "test@test.com"

# Create initial commit and tag
echo '{"version":"1.0.0"}' > package.json
git add . && git commit -m "initial: setup"
git tag v1.0.0

# Add feature commit
echo "feature" > feature.txt
git add feature.txt
git commit -m "feat: add feature"

# Test the bumper
cd ..
bun run src/index.ts \
  --version-file test-repo/package.json \
  --previous-tag v1.0.0
```

## Support & Documentation

- See `IMPLEMENTATION_SUMMARY.md` for detailed implementation info
- Check individual test files for usage examples
- Review `src/index.ts` comments for CLI option details

## Quick Checklist

- ✅ Tests pass: `bun test`
- ✅ Workflow valid: `actionlint .github/workflows/semantic-version-bumper.yml`
- ✅ Tool works: `bun run src/index.ts --version-file package.json --previous-tag v1.0.0 --dry-run`
- ✅ Cleanup temp files: `rm -rf test-repo` (if created)
