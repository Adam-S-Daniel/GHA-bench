const path = require('path');
const fs = require('fs');
const os = require('os');
const { execSync } = require('child_process');
const {
  parseVersion,
  getNextVersion,
  updateVersionFile,
  generateChangelog,
  getConventionalCommits,
} = require('../src/semantic-version-bumper');

describe('semantic-version-bumper', () => {
  // Test 1: Parse version from package.json
  describe('parseVersion', () => {
    it('should parse version from package.json', () => {
      const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'svb-'));
      const packagePath = path.join(tempDir, 'package.json');
      fs.writeFileSync(packagePath, JSON.stringify({ version: '1.0.0' }));

      const version = parseVersion(packagePath);
      expect(version).toBe('1.0.0');

      fs.rmSync(tempDir, { recursive: true });
    });

    it('should parse version from VERSION file', () => {
      const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'svb-'));
      const versionPath = path.join(tempDir, 'VERSION');
      fs.writeFileSync(versionPath, '2.1.3\n');

      const version = parseVersion(versionPath);
      expect(version).toBe('2.1.3');

      fs.rmSync(tempDir, { recursive: true });
    });
  });

  // Test 2: Get next version based on commit types
  describe('getNextVersion', () => {
    it('should bump patch version for fix commits', () => {
      const nextVersion = getNextVersion('1.0.0', [
        { type: 'fix', message: 'fix: database connection' },
      ]);
      expect(nextVersion).toBe('1.0.1');
    });

    it('should bump minor version for feat commits', () => {
      const nextVersion = getNextVersion('1.0.0', [
        { type: 'feat', message: 'feat: add user authentication' },
      ]);
      expect(nextVersion).toBe('1.1.0');
    });

    it('should bump major version for breaking changes', () => {
      const nextVersion = getNextVersion('1.0.0', [
        { type: 'feat', message: 'remove legacy API', isBreaking: true },
      ]);
      expect(nextVersion).toBe('2.0.0');
    });

    it('should use highest bump when multiple commit types', () => {
      const nextVersion = getNextVersion('1.2.3', [
        { type: 'fix', message: 'fix: bug' },
        { type: 'feat', message: 'feat: feature' },
      ]);
      expect(nextVersion).toBe('1.3.0');
    });
  });

  // Test 3: Update version file
  describe('updateVersionFile', () => {
    it('should update version in package.json', () => {
      const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'svb-'));
      const packagePath = path.join(tempDir, 'package.json');
      fs.writeFileSync(packagePath, JSON.stringify({ version: '1.0.0', name: 'test' }, null, 2));

      updateVersionFile(packagePath, '1.1.0');

      const content = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
      expect(content.version).toBe('1.1.0');

      fs.rmSync(tempDir, { recursive: true });
    });

    it('should update version in VERSION file', () => {
      const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'svb-'));
      const versionPath = path.join(tempDir, 'VERSION');
      fs.writeFileSync(versionPath, '1.0.0\n');

      updateVersionFile(versionPath, '1.1.0');

      const content = fs.readFileSync(versionPath, 'utf8').trim();
      expect(content).toBe('1.1.0');

      fs.rmSync(tempDir, { recursive: true });
    });
  });

  // Test 4: Parse conventional commits
  describe('getConventionalCommits', () => {
    it('should parse conventional commit messages', () => {
      const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'svb-'));
      const originalDir = process.cwd();
      process.chdir(tempDir);

      try {
        // Initialize git repo
        execSync('git init', { stdio: 'pipe' });
        execSync('git config user.email "test@example.com"', { stdio: 'pipe' });
        execSync('git config user.name "Test User"', { stdio: 'pipe' });

        // Create initial commit
        fs.writeFileSync(path.join(tempDir, 'test.txt'), 'content');
        execSync('git add test.txt', { stdio: 'pipe' });
        execSync('git commit -m "Initial commit"', { stdio: 'pipe' });

        // Create feat commit
        fs.writeFileSync(path.join(tempDir, 'test.txt'), 'content2');
        execSync('git add test.txt', { stdio: 'pipe' });
        execSync('git commit -m "feat: add new feature"', { stdio: 'pipe' });

        // Create fix commit
        fs.writeFileSync(path.join(tempDir, 'test.txt'), 'content3');
        execSync('git add test.txt', { stdio: 'pipe' });
        execSync('git commit -m "fix: resolve bug"', { stdio: 'pipe' });

        const commits = getConventionalCommits('HEAD~2');
        expect(commits).toHaveLength(2);
        // git log returns newest first, so fix is first, feat is second
        expect(commits[0].type).toBe('fix');
        expect(commits[1].type).toBe('feat');
      } finally {
        process.chdir(originalDir);
        fs.rmSync(tempDir, { recursive: true });
      }
    });
  });

  // Test 5: Generate changelog
  describe('generateChangelog', () => {
    it('should generate changelog from commits', () => {
      const commits = [
        { type: 'feat', message: 'feat: add authentication' },
        { type: 'fix', message: 'fix: database bug' },
      ];

      const changelog = generateChangelog('1.1.0', commits);
      expect(changelog).toContain('1.1.0');
      expect(changelog).toContain('add authentication');
      expect(changelog).toContain('database bug');
    });

    it('should categorize commits by type in changelog', () => {
      const commits = [
        { type: 'feat', message: 'feat: feature one' },
        { type: 'feat', message: 'feat: feature two' },
        { type: 'fix', message: 'fix: fix one' },
      ];

      const changelog = generateChangelog('1.2.0', commits);
      expect(changelog).toContain('Features');
      expect(changelog).toContain('Bug Fixes');
      expect(changelog).toContain('feature one');
      expect(changelog).toContain('feature two');
      expect(changelog).toContain('fix one');
    });
  });
});
