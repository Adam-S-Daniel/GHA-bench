# Semantic Version Bumper - Project Index

## Quick Start

```bash
# Run all 36 tests
bun test *.test.ts

# Run CLI
bun cli.ts --version-file package.json --git-range origin/main..HEAD

# Test GitHub Actions workflow locally
act push --rm -j test
```

## File Organization

### Core Implementation
- **`version-bumper.ts`** (211 lines)
  - `parseVersion()` - Parse semantic version strings
  - `parseConventionalCommits()` - Extract commit metadata
  - `determineNextVersion()` - Apply SemVer rules
  - `updateVersionFile()` - Write version to file
  - `generateChangelog()` - Create markdown changelog
  - `bumpVersion()` - Main orchestration function

- **`cli.ts`** (125 lines)
  - Command-line interface with argument parsing
  - Git integration for commit range detection
  - Dry-run mode support
  - Help text and error handling

- **`test-fixtures.ts`** (128 lines)
  - 9 test scenarios covering all version bump types
  - Mock git repository generator
  - Comprehensive fixture data

### Testing (36 tests total)

#### Unit Tests - `version-bumper.test.ts` (23 tests)
- parseVersion (5 tests)
- determineNextVersion (4 tests)
- parseConventionalCommits (4 tests)
- updateVersionFile (3 tests)
- generateChangelog (4 tests)
- bumpVersion (3 tests)

#### Integration Tests - `integration.test.ts` (13 tests)
- Patch/minor/major version bumping
- Breaking change detection
- Scope handling
- Pre-release versions
- File format preservation
- Changelog formatting

### GitHub Actions
- **`.github/workflows/semantic-version-bumper.yml`** (189 lines)
  - `test` job: Unit + integration tests
  - `bump-version` job: Version detection on main branch
  - `test-scenarios` job: 3-matrix validation (patch/minor/major)

### Documentation
- **`README.md`** (162 lines) - Complete usage guide
- **`REQUIREMENTS_CHECKLIST.md`** (253 lines) - Full compliance verification
- **`FINAL_SUMMARY.txt`** (340 lines) - Comprehensive project summary
- **`INDEX.md`** (this file) - Quick navigation

### Utilities & Artifacts
- **`run-act-tests.sh`** (131 lines) - Local workflow test harness
- **`act-result.txt`** (389 lines) - Complete workflow test output

## Test Coverage

### Scenarios Tested

1. **Patch Version Bump** (fix commit)
   - Input: 1.0.0 + "fix: bug"
   - Output: 1.0.1

2. **Minor Version Bump** (feat commit)
   - Input: 1.0.0 + "feat: feature"
   - Output: 1.1.0

3. **Major Version Bump** (breaking with !)
   - Input: 1.0.0 + "feat!: breaking"
   - Output: 2.0.0

4. **Major Version Bump** (breaking footer)
   - Input: 2.1.0 + "feat: feature\n\nBREAKING CHANGE: ..."
   - Output: 3.0.0

5. **Mixed Commits**
   - Multiple feat + fix + breaking changes
   - Highest priority bump wins

6. **Non-Conventional Commits**
   - No version bump for unrecognized formats

7. **Scoped Commits**
   - feat(api), fix(cli) style parsing

8. **Pre-Release Versions**
   - 1.0.0-alpha handling

9. **Real-World Scenario**
   - Mix of all commit types (8 commits)

## Key Features

✓ **Semantic Versioning** - Full SemVer 2.0 support
✓ **Conventional Commits** - Follows CC 1.0 spec
✓ **Breaking Changes** - Detects via ! and footer
✓ **Scope Support** - type(scope): message format
✓ **File Formats** - package.json and VERSION files
✓ **Changelog Generation** - Grouped markdown output
✓ **Error Handling** - Graceful with descriptive messages
✓ **TypeScript** - Full type safety, no implicit any
✓ **TDD Methodology** - Red-green development
✓ **CI/CD Ready** - GitHub Actions workflow included

## Performance

- **36 tests**: < 100ms total
- **Workflow job**: ~3.6 seconds (including Docker setup)
- **Scenario tests**: ~300ms each

## API Reference

### Main Functions

```typescript
parseVersion(versionStr: string): SemanticVersion
- Input: "1.2.3", "v1.2.3", or "1.0.0-alpha"
- Output: { major: 1, minor: 2, patch: 3 }

parseConventionalCommits(messages: string[]): ParsedCommit[]
- Input: ["feat: new feature", "fix!: breaking fix"]
- Output: Parsed commit objects with type, scope, message, breaking flag

determineNextVersion(current: SemanticVersion, commits: string[]): SemanticVersion
- Input: Current version + commit messages
- Output: Next version following SemVer rules

updateVersionFile(filePath: string, newVersion: string): void
- Updates version in package.json or VERSION file

generateChangelog(version: string, commits: string[]): string
- Creates markdown changelog grouped by type

bumpVersion(filePath: string, commits: string[]): BumpResult
- Orchestrates entire version bump workflow
- Returns: { oldVersion, newVersion, changelog }
```

## Compliance Checklist

✓ Red-green TDD methodology
✓ All 36 tests passing
✓ Full TypeScript type coverage
✓ Graceful error handling
✓ GitHub Actions workflow
✓ actionlint validation passing
✓ Act testing successful
✓ Test fixtures included
✓ Complete documentation
✓ Production-ready code

## Usage Examples

### Via CLI
```bash
# Auto-detect version file and git range
bun cli.ts

# Specify version file
bun cli.ts --version-file package.json

# Specify git range
bun cli.ts --git-range origin/main..HEAD

# Dry-run mode
bun cli.ts --dry-run

# Help text
bun cli.ts --help
```

### Via Module
```typescript
import { bumpVersion } from './version-bumper';

const result = bumpVersion('package.json', [
  'feat: new caching layer',
  'fix: memory leak',
  'feat: new endpoint'
]);

console.log(`${result.oldVersion} → ${result.newVersion}`);
console.log(result.changelog);
```

## Conventional Commit Examples

### Recognized Types
- `feat` → Feature (minor bump)
- `fix` → Bug fix (patch bump)
- `feat!` → Breaking feature (major bump)
- `fix!` → Breaking fix (major bump)
- `BREAKING CHANGE:` → Footer (major bump)

### Example Commits
```
fix: resolve memory leak
feat: add caching layer
feat(api): add pagination endpoint
fix(cli): correct argument parsing
feat!: change API response format
feat: new feature

BREAKING CHANGE: response structure has changed
```

## Testing Commands

```bash
# Run all tests
bun test *.test.ts

# Run unit tests only
bun test version-bumper.test.ts

# Run integration tests only
bun test integration.test.ts

# Run GitHub Actions workflow (requires act and Docker)
act push --rm -j test
act push --rm -j test-scenarios

# Run local test harness
./run-act-tests.sh

# Validate workflow syntax
actionlint .github/workflows/semantic-version-bumper.yml
```

## Project Statistics

- **Total Lines**: ~1,700
- **Production Code**: ~340 lines
- **Test Code**: ~440 lines
- **Workflow/Scripts**: ~320 lines
- **Documentation**: ~600 lines
- **Files**: 12 core files + documentation

## Requirements Fulfilled

1. ✓ Parse version file (package.json/VERSION)
2. ✓ Determine next version from commits
3. ✓ Update version file
4. ✓ Generate changelog
5. ✓ Output new version
6. ✓ Red-green TDD methodology
7. ✓ All tests pass with `bun test`
8. ✓ Clear comments explaining approach
9. ✓ Graceful error handling
10. ✓ TypeScript with explicit types
11. ✓ GitHub Actions workflow
12. ✓ actionlint validation
13. ✓ Act testing successful
14. ✓ Test fixtures created
15. ✓ act-result.txt artifact

---

**Status**: ✅ Complete and Ready for Production
