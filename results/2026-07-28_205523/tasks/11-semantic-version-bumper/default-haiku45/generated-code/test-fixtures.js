// Test fixtures for semantic version bumper
// Provides mock commits and test scenarios

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Test case 1: Patch bump (only fixes)
const patchBumpFixture = {
  name: 'patch-bump-fixture',
  initialVersion: '1.0.0',
  commits: [
    { message: 'fix: corrected typo in docs' },
    { message: 'fix: resolved memory leak in worker' }
  ],
  expectedVersion: '1.0.2',
  expectedChangelog: {
    contains: ['1.0.2', 'Bug Fixes', 'typo', 'memory leak']
  }
};

// Test case 2: Minor bump (features)
const minorBumpFixture = {
  name: 'minor-bump-fixture',
  initialVersion: '1.2.0',
  commits: [
    { message: 'feat: added user authentication' },
    { message: 'fix: improved error handling' }
  ],
  expectedVersion: '1.3.0',
  expectedChangelog: {
    contains: ['1.3.0', 'Features', 'authentication', 'Bug Fixes']
  }
};

// Test case 3: Major bump (breaking changes)
const majorBumpFixture = {
  name: 'major-bump-fixture',
  initialVersion: '2.1.3',
  commits: [
    { message: 'feat: redesigned API\n\nBREAKING CHANGE: removed deprecated v1 endpoints' },
    { message: 'feat: added new authentication flow' }
  ],
  expectedVersion: '3.0.0',
  expectedChangelog: {
    contains: ['3.0.0', 'BREAKING', 'removed deprecated']
  }
};

// Test case 4: No commits
const noCommitsFixture = {
  name: 'no-commits-fixture',
  initialVersion: '1.0.0',
  commits: [],
  expectedVersion: '1.0.0',
  shouldSkip: true
};

// Test case 5: Mixed commits with chore (should be ignored)
const mixedCommitsFixture = {
  name: 'mixed-commits-fixture',
  initialVersion: '1.0.0',
  commits: [
    { message: 'chore: updated dependencies' },
    { message: 'docs: updated README' },
    { message: 'fix: corrected validation logic' },
    { message: 'feat: added API rate limiting' }
  ],
  expectedVersion: '1.1.0',
  expectedChangelog: {
    contains: ['1.1.0', 'Features', 'Bug Fixes'],
    notContains: ['chore', 'dependencies', 'README']
  }
};

// Test case 6: Complex scenario with all types
const complexFixture = {
  name: 'complex-fixture',
  initialVersion: '0.5.0',
  commits: [
    { message: 'fix: array bounds check' },
    { message: 'feat: added search functionality' },
    { message: 'feat: implemented caching\n\nBREAKING CHANGE: cache API changed' },
    { message: 'fix: null pointer exception' }
  ],
  expectedVersion: '1.0.0',
  expectedChangelog: {
    contains: ['1.0.0', 'BREAKING', 'Features', 'Bug Fixes']
  }
};

const fixtures = [
  patchBumpFixture,
  minorBumpFixture,
  majorBumpFixture,
  noCommitsFixture,
  mixedCommitsFixture,
  complexFixture
];

// Helper: Setup git repo with test fixture
function setupFixtureRepo(fixture, testDir) {
  // Initialize git repo
  execSync('git init', { cwd: testDir, stdio: 'pipe' });
  execSync('git config user.email "test@example.com"', { cwd: testDir, stdio: 'pipe' });
  execSync('git config user.name "Test User"', { cwd: testDir, stdio: 'pipe' });

  // Create initial package.json
  const pkg = {
    name: fixture.name,
    version: fixture.initialVersion
  };
  fs.writeFileSync(path.join(testDir, 'package.json'), JSON.stringify(pkg, null, 2));
  execSync('git add package.json', { cwd: testDir, stdio: 'pipe' });
  execSync('git commit -m "initial commit"', { cwd: testDir, stdio: 'pipe' });

  // Add fixture commits
  for (let i = 0; i < fixture.commits.length; i++) {
    const commit = fixture.commits[i];
    // Create a dummy file change to have something to commit
    const filename = `file${i}.txt`;
    fs.writeFileSync(path.join(testDir, filename), `Change ${i}\n`);
    execSync(`git add ${filename}`, { cwd: testDir, stdio: 'pipe' });

    // Use --allow-empty-message for commits without body
    const message = commit.message.replace(/\n/g, '\n');
    execSync(`git commit -m "${message.replace(/"/g, '\\"')}"`, {
      cwd: testDir,
      stdio: 'pipe',
      shell: '/bin/bash'
    });
  }
}

module.exports = {
  fixtures,
  patchBumpFixture,
  minorBumpFixture,
  majorBumpFixture,
  noCommitsFixture,
  mixedCommitsFixture,
  complexFixture,
  setupFixtureRepo
};
