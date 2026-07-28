# Testing Documentation

## Overview

This project uses a test-driven development (TDD) approach with comprehensive test coverage. All tests are implemented using [bats-core](https://github.com/bats-core/bats-core) and can be run locally or in the GitHub Actions CI/CD pipeline.

## Unit Tests (20 total)

### Core Functionality Tests

#### Version Parsing (2 tests)
1. **parse_version extracts major.minor.patch from version string**
   - Tests that a version string like "1.2.3" is correctly parsed
   - Validates each component (major=1, minor=2, patch=3)

2. **parse_version rejects invalid version format**
   - Tests that malformed versions (e.g., "1.2") are rejected
   - Validates error exit code

#### Commit Type Detection (4 tests)
3. **get_commit_type identifies feat commits as minor**
   - Tests that "feat: add feature" returns "minor"
   
4. **get_commit_type identifies fix commits as patch**
   - Tests that "fix: resolve bug" returns "patch"
   
5. **get_commit_type identifies breaking changes as major**
   - Tests that "feat!: breaking change" returns "major"
   
6. **get_commit_type identifies BREAKING CHANGE in body as major**
   - Tests multiline commits with "BREAKING CHANGE:" in body
   - Returns "major" for any commit with breaking indicator

#### Version Bumping (3 tests)
7. **bump_version increments patch for patch bump**
   - Tests: "1.2.3" + patch → "1.2.4"
   
8. **bump_version increments minor for minor bump and resets patch**
   - Tests: "1.2.3" + minor → "1.3.0"
   - Validates patch is reset to 0
   
9. **bump_version increments major for major bump and resets minor and patch**
   - Tests: "1.2.3" + major → "2.0.0"
   - Validates minor and patch are reset

#### File I/O (2 tests)
10. **read_version_from_package_json reads version from package.json**
    - Reads `{"version":"2.1.0"}` and extracts "2.1.0"
    - Validates JSON parsing

11. **write_version_to_package_json updates package.json version**
    - Updates version from "1.0.0" to "1.1.0"
    - Validates the file is modified correctly

#### Version Priority (2 tests)
12. **get_highest_bump_type returns major when both major and minor present**
    - Tests priority: major > minor > patch
    
13. **get_highest_bump_type returns minor when minor and patch present**
    - Tests priority ordering

#### Git Integration (2 tests)
14. **get_conventional_commits finds feat commits in git log**
    - Creates a test git repo with conventional commits
    - Validates commit log parsing
    
15. **generate_changelog creates formatted changelog entry**
    - Tests changelog formatting with version and date

#### Integration Tests (4 tests)
16. **semantic-version-bumper.sh bumps version with feat commit**
    - End-to-end test: feat commit → version bump to 1.1.0
    - Validates package.json is updated
    
17. **semantic-version-bumper.sh bumps version with fix commit**
    - End-to-end test: fix commit → version bump to 1.0.1
    
18. **semantic-version-bumper.sh bumps version with breaking change**
    - End-to-end test: breaking change → version bump to 2.0.0
    
19. **semantic-version-bumper.sh dry-run doesn't modify files**
    - Validates dry-run mode doesn't change package.json
    
20. **semantic-version-bumper.sh creates changelog**
    - Validates CHANGELOG.md is created with version info

## Running Tests

### Local Execution

```bash
# Run all tests
bats test/version_bumper.bats

# Run with verbose output
bats test/version_bumper.bats --verbose

# Run single test
bats test/version_bumper.bats --filter "parse_version extracts"
```

### GitHub Actions Execution

```bash
# Run via act (local Docker simulation)
act push

# Run specific job
act push -j test
act push -j integration
```

## Test Fixtures

Each test creates isolated git repositories using temporary directories:

```bash
setup() {
  export TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_GIT_DIR="$TEST_TEMP_DIR/test-repo"
  mkdir -p "$TEST_GIT_DIR"
  cd "$TEST_GIT_DIR"
  
  git init
  git config user.email "test@example.com"
  git config user.name "Test User"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}
```

This ensures:
- Tests are isolated from system state
- No side effects on real repositories
- Clean environment for each test
- Automatic cleanup after test completion

## Test Coverage

### Functions Tested
- ✅ `parse_version()` - Version string parsing
- ✅ `get_commit_type()` - Commit message analysis
- ✅ `bump_version()` - Version calculation
- ✅ `read_version_from_package_json()` - File I/O read
- ✅ `write_version_to_package_json()` - File I/O write
- ✅ `get_highest_bump_type()` - Priority logic
- ✅ `get_conventional_commits()` - Git integration
- ✅ `generate_changelog()` - Changelog generation
- ✅ `main()` - Full integration

### Scenarios Covered
- ✅ Valid semantic versions
- ✅ Invalid version formats
- ✅ All commit types (feat, fix, breaking)
- ✅ Version bumping for each component
- ✅ File reading and writing
- ✅ Git log parsing
- ✅ Changelog generation
- ✅ Dry-run mode
- ✅ Error cases

## GitHub Actions Workflow

The workflow file `.github/workflows/semantic-version-bumper.yml` includes:

### Test Job
Runs on each `push` and `pull_request`:
- Installs bats and shellcheck
- Validates bash syntax (`bash -n`)
- Runs shellcheck for code quality
- Executes all 20 unit tests

### Integration Job
Comprehensive end-to-end tests:
- Creates real git repositories
- Makes commits with specific messages
- Validates version bumping
- Tests dry-run mode
- Verifies changelog generation

### Validation Steps
All tests must pass before job completes:
- Syntax validation: ✅
- Shellcheck: ✅ (informational)
- 20 unit tests: ✅
- 5 integration scenarios: ✅

## Continuous Integration

### Local Validation
```bash
# Quick validation before committing
bash -n bin/version-bumper.sh
bash -n bin/semantic-version-bumper.sh
bats test/version_bumper.bats
```

### CI/CD Validation
```bash
# Full pipeline test with act
act push
```

The workflow automatically runs on:
- Every push to main/master
- Every pull request
- Manual trigger via workflow_dispatch

## Expected Output

### Successful Test Run
```
1..20
ok 1 parse_version extracts major.minor.patch from version string
ok 2 parse_version rejects invalid version format
...
ok 20 semantic-version-bumper.sh creates changelog
```

### Successful Workflow Run
```
[Semantic Version Bumper/Test semantic version bumper] ✅ Success - Main Run tests
[Semantic Version Bumper/Integration test with real workflow] ✅ Success - Main Test version bump - feat commit
...
🏁 Job succeeded (2 jobs)
```

## Troubleshooting

### Test Failures

If a test fails:
1. Check the error message in bats output
2. Review the test case in `test/version_bumper.bats`
3. Verify the implementation in `bin/version-bumper.sh`
4. Look for recent commits that might have broken it

### Common Issues

**"git describe not found" warning**
- Normal during initial development before first tag
- Tests create tags when needed

**"unable to get git ref" in act output**
- Normal - act runs in isolated container
- Tests still execute successfully

**shellcheck warnings**
- Most are informational (SC1091)
- Scripts are validated to work correctly
- No breaking issues

## Test Maintenance

When adding new features:
1. Write test first (RED phase)
2. Implement minimum code (GREEN phase)
3. Refactor for clarity (REFACTOR phase)
4. Ensure all 20 tests still pass
5. Update this documentation

## Performance

Test execution times:
- Unit tests: ~2-3 seconds
- GitHub Actions test job: ~20 seconds
- GitHub Actions integration job: ~30-40 seconds
- Full workflow (both jobs): ~40-60 seconds

All tests must complete within GitHub Actions timeout (no issues expected).
