// Test fixtures for semantic version bumper

export const fixtures = {
  // Basic patch bump scenario
  patchBump: {
    name: "patch-bump",
    currentVersion: "1.0.0",
    commits: ["fix: resolve memory leak in parser"],
    expectedVersion: "1.0.1",
    expectedChangelog: ["1.0.1", "Bug Fixes", "resolve memory leak"],
  },

  // Minor bump with multiple commits
  minorBump: {
    name: "minor-bump",
    currentVersion: "1.0.0",
    commits: [
      "feat: add new caching layer",
      "fix: correct validation logic",
      "docs: update README",
    ],
    expectedVersion: "1.1.0",
    expectedChangelog: ["1.1.0", "Features", "add new caching layer"],
  },

  // Major bump for breaking changes (exclamation mark syntax)
  majorBumpExclamation: {
    name: "major-bump-exclamation",
    currentVersion: "1.5.2",
    commits: [
      "feat!: change API response format",
      "feat: add new endpoint",
      "fix: bug fix",
    ],
    expectedVersion: "2.0.0",
    expectedChangelog: ["2.0.0", "Features", "change API response format"],
  },

  // Major bump for breaking changes (BREAKING CHANGE footer)
  majorBumpFooter: {
    name: "major-bump-footer",
    currentVersion: "2.1.0",
    commits: [
      "feat: add new feature\n\nBREAKING CHANGE: this breaks the existing API",
    ],
    expectedVersion: "3.0.0",
    expectedChangelog: ["3.0.0", "add new feature"],
  },

  // Mixed breaking and regular changes
  mixedCommits: {
    name: "mixed-commits",
    currentVersion: "0.5.0",
    commits: [
      "fix!: change database schema",
      "feat: new authentication method",
      "fix: validation error",
      "docs: update API docs",
    ],
    expectedVersion: "1.0.0",
    expectedChangelog: ["1.0.0", "change database schema"],
  },

  // No conventional commits (should not bump)
  noConventionalCommits: {
    name: "no-conventional-commits",
    currentVersion: "1.0.0",
    commits: ["Update README", "Cleanup code"],
    expectedVersion: "1.0.0",
    expectedChangelog: ["1.0.0"],
  },

  // Commits with scope
  withScope: {
    name: "with-scope",
    currentVersion: "1.0.0",
    commits: [
      "feat(api): add pagination support",
      "fix(cli): resolve argument parsing",
    ],
    expectedVersion: "1.1.0",
    expectedChangelog: ["1.1.0", "add pagination support"],
  },

  // Pre-release version
  preReleaseToRelease: {
    name: "prerelease-to-release",
    currentVersion: "1.0.0-alpha",
    commits: ["fix: critical bug"],
    expectedVersion: "1.0.1",
    expectedChangelog: ["1.0.1", "critical bug"],
  },

  // Large version bumps from small base
  largeMinorJump: {
    name: "large-minor-jump",
    currentVersion: "0.1.0",
    commits: ["feat: major refactor", "feat: new module", "fix: small fix"],
    expectedVersion: "0.2.0",
    expectedChangelog: ["0.2.0", "major refactor", "new module"],
  },

  // Scenario: from tag to HEAD with real-world commits
  realWorldScenario: {
    name: "real-world-scenario",
    currentVersion: "1.2.3",
    commits: [
      "chore: update dependencies",
      "feat: implement streaming API",
      "fix: handle null values correctly",
      "test: add integration tests",
      "feat(auth): add OAuth2 support",
      "docs: document OAuth2 setup",
      "refactor: simplify parser logic",
      "fix: prevent race condition",
    ],
    expectedVersion: "1.3.0",
    expectedChangelog: [
      "1.3.0",
      "Features",
      "implement streaming API",
      "add OAuth2 support",
    ],
  },
};

// Mock git repositories for testing CLI
export function createMockGitRepo(
  repoPath: string,
  commits: Array<{ msg: string; author: string }>
): void {
  const fs = require("fs");
  const { execSync } = require("child_process");

  // Initialize repo
  if (!fs.existsSync(repoPath)) {
    fs.mkdirSync(repoPath, { recursive: true });
  }

  execSync("git init", { cwd: repoPath });
  execSync('git config user.email "test@example.com"', { cwd: repoPath });
  execSync('git config user.name "Test User"', { cwd: repoPath });

  // Create initial commit
  fs.writeFileSync(`${repoPath}/package.json`, '{"name":"test","version":"1.0.0"}\n');
  execSync("git add package.json", { cwd: repoPath });
  execSync('git commit -m "initial commit"', { cwd: repoPath });

  // Add commits
  for (const commit of commits) {
    fs.writeFileSync(`${repoPath}/file-${Date.now()}.txt`, commit.msg);
    execSync("git add .", { cwd: repoPath });
    execSync(`git commit -m "${commit.msg}"`, { cwd: repoPath });
  }
}
