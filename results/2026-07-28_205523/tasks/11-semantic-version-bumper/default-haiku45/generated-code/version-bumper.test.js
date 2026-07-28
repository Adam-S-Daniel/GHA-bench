// Test suite for semantic version bumper
// TDD approach: write failing tests first, then implement

const fs = require('fs');
const path = require('path');
const {
  parseVersion,
  determineVersionBump,
  updateVersion,
  generateChangelogEntry,
  runVersionBumper
} = require('./version-bumper');

describe('Semantic Version Bumper', () => {
  let testDir;

  beforeEach(() => {
    testDir = path.join(__dirname, 'test-workspace-' + Date.now());
    fs.mkdirSync(testDir, { recursive: true });
    process.chdir(testDir);
  });

  afterEach(() => {
    process.chdir('/');
    fs.rmSync(testDir, { recursive: true, force: true });
  });

  // TEST 1: Parse version from package.json
  describe('parseVersion', () => {
    test('should parse version from package.json', () => {
      fs.writeFileSync('package.json', JSON.stringify({ version: '1.2.3' }, null, 2));
      const version = parseVersion();
      expect(version).toBe('1.2.3');
    });

    test('should parse version from version file', () => {
      fs.writeFileSync('VERSION', '2.0.0\n');
      const version = parseVersion('VERSION');
      expect(version).toBe('2.0.0');
    });

    test('should throw error if no version file found', () => {
      expect(() => parseVersion()).toThrow();
    });
  });

  // TEST 2: Determine version bump from commits
  describe('determineVersionBump', () => {
    test('should return patch for fix commits', () => {
      const commits = [
        { message: 'fix: corrected typo in docs' }
      ];
      const bump = determineVersionBump(commits);
      expect(bump).toBe('patch');
    });

    test('should return minor for feat commits', () => {
      const commits = [
        { message: 'feat: added new API endpoint' }
      ];
      const bump = determineVersionBump(commits);
      expect(bump).toBe('minor');
    });

    test('should return major for breaking change commits', () => {
      const commits = [
        { message: 'feat: redesigned API\n\nBREAKING CHANGE: removed deprecated endpoints' }
      ];
      const bump = determineVersionBump(commits);
      expect(bump).toBe('major');
    });

    test('should return major for BREAKING CHANGE: prefix', () => {
      const commits = [
        { message: 'BREAKING CHANGE: removed auth middleware' }
      ];
      const bump = determineVersionBump(commits);
      expect(bump).toBe('major');
    });

    test('should return major when multiple commits include breaking change', () => {
      const commits = [
        { message: 'fix: small fix' },
        { message: 'feat: new feature\n\nBREAKING CHANGE: removed old feature' }
      ];
      const bump = determineVersionBump(commits);
      expect(bump).toBe('major');
    });

    test('should prioritize: breaking > minor > patch', () => {
      const commits = [
        { message: 'fix: small fix' },
        { message: 'feat: new feature' },
        { message: 'chore: updated dependencies' }
      ];
      const bump = determineVersionBump(commits);
      expect(bump).toBe('minor');
    });
  });

  // TEST 3: Calculate next version
  describe('calculateNextVersion', () => {
    const { calculateNextVersion } = require('./version-bumper');

    test('should bump patch version', () => {
      const next = calculateNextVersion('1.2.3', 'patch');
      expect(next).toBe('1.2.4');
    });

    test('should bump minor version and reset patch', () => {
      const next = calculateNextVersion('1.2.3', 'minor');
      expect(next).toBe('1.3.0');
    });

    test('should bump major version and reset minor/patch', () => {
      const next = calculateNextVersion('1.2.3', 'major');
      expect(next).toBe('2.0.0');
    });

    test('should handle version bumps from 1.0.0', () => {
      const next = calculateNextVersion('1.0.0', 'patch');
      expect(next).toBe('1.0.1');
    });
  });

  // TEST 4: Update version in files
  describe('updateVersion', () => {
    test('should update version in package.json', () => {
      fs.writeFileSync('package.json', JSON.stringify({ version: '1.0.0', name: 'test' }, null, 2));
      updateVersion('1.0.1', 'package.json');
      const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
      expect(pkg.version).toBe('1.0.1');
    });

    test('should update version in VERSION file', () => {
      fs.writeFileSync('VERSION', '1.0.0\n');
      updateVersion('1.0.1', 'VERSION');
      const version = fs.readFileSync('VERSION', 'utf8').trim();
      expect(version).toBe('1.0.1');
    });

    test('should preserve other fields in package.json', () => {
      const pkg = { version: '1.0.0', name: 'myapp', description: 'test' };
      fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
      updateVersion('1.0.1', 'package.json');
      const updated = JSON.parse(fs.readFileSync('package.json', 'utf8'));
      expect(updated.name).toBe('myapp');
      expect(updated.description).toBe('test');
    });
  });

  // TEST 5: Generate changelog entry
  describe('generateChangelogEntry', () => {
    test('should format changelog entry with version and date', () => {
      const commits = [
        { message: 'feat: added user authentication' },
        { message: 'fix: corrected email validation' }
      ];
      const changelog = generateChangelogEntry('1.1.0', commits);
      expect(changelog).toContain('1.1.0');
      expect(changelog).toContain('Features');
      expect(changelog).toContain('added user authentication');
      expect(changelog).toContain('Bug Fixes');
      expect(changelog).toContain('corrected email validation');
    });

    test('should handle breaking changes in changelog', () => {
      const commits = [
        { message: 'feat: redesigned API\n\nBREAKING CHANGE: removed v1 endpoints' }
      ];
      const changelog = generateChangelogEntry('2.0.0', commits);
      expect(changelog).toContain('BREAKING');
      expect(changelog).toContain('removed v1 endpoints');
    });

    test('should skip chore commits in changelog', () => {
      const commits = [
        { message: 'chore: updated dependencies' },
        { message: 'feat: added feature' }
      ];
      const changelog = generateChangelogEntry('1.1.0', commits);
      expect(changelog).toContain('added feature');
      expect(changelog).not.toContain('updated dependencies');
    });
  });

  // TEST 6: Full integration test
  describe('runVersionBumper', () => {
    test('should bump version and generate changelog', () => {
      // Setup: create package.json with initial version
      fs.writeFileSync('package.json', JSON.stringify({ version: '1.0.0' }, null, 2));
      fs.mkdirSync('.git', { recursive: true });

      // Create mock commits
      const commits = [
        { message: 'feat: added new feature' }
      ];

      const result = runVersionBumper(commits);
      expect(result.newVersion).toBe('1.1.0');
      expect(result.changelog).toBeDefined();
      expect(result.changelog).toContain('1.1.0');

      // Verify file was updated
      const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
      expect(pkg.version).toBe('1.1.0');
    });
  });
});
