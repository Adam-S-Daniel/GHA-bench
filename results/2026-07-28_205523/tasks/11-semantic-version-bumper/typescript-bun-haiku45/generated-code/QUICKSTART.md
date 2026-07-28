# Quick Start Guide

## Installation
```bash
bun install
```

## Run Tests
```bash
bun test
# Result: 31 pass, 0 fail
```

## Run Version Bumper
```bash
bun run src/index.ts
# or with options:
bun run src/index.ts --package-json package.json --last-tag v1.0.0
```

## Test GitHub Actions Workflow
```bash
# Validate workflow
actionlint .github/workflows/semantic-version-bumper.yml

# Run locally with act
./test-workflow.sh

# Check results
cat act-result.txt
```

## Project Structure
```
src/
  ├── version.ts          # Version parsing/bumping
  ├── commits.ts          # Commit analysis
  ├── changelog.ts        # Changelog generation
  ├── files.ts            # File I/O
  ├── git.ts              # Git operations
  ├── index.ts            # Main CLI
  ├── fixtures.ts         # Test fixtures
  └── *.test.ts           # Unit tests

.github/workflows/
  └── semantic-version-bumper.yml   # GitHub Actions

Documentation/
  ├── README.md           # Full documentation
  ├── VERIFICATION.md     # Requirements checklist
  ├── PROJECT_SUMMARY.md  # Project overview
  └── QUICKSTART.md       # This file
```

## Test Coverage
- 31 unit tests
- 41 assertions
- 7 test fixture scenarios
- 100% pass rate

## What It Does
1. Reads current version from package.json
2. Analyzes commits since last tag
3. Determines version bump (major/minor/patch)
4. Updates package.json
5. Generates CHANGELOG.md entry
6. Outputs new version

## Conventional Commits
- `feat:` → minor bump (1.0.0 → 1.1.0)
- `fix:` → patch bump (1.0.0 → 1.0.1)
- `feat!:` or `BREAKING CHANGE:` → major bump (1.0.0 → 2.0.0)

## CI/CD
The workflow runs on:
- Push to main/master
- Pull requests to main/master
- Manual trigger (workflow_dispatch)

Both jobs succeed:
- test: Runs bun test
- bump-version: Bumps version and generates changelog

## Key Files
- `act-result.txt` - Test results from act workflow
- `package.json` - Version is stored here
- `CHANGELOG.md` - Auto-generated changelog
- `.github/workflows/semantic-version-bumper.yml` - GitHub Actions workflow

## Verification
All requirements met ✅
All tests passing ✅
Workflow valid ✅
Act testing working ✅
