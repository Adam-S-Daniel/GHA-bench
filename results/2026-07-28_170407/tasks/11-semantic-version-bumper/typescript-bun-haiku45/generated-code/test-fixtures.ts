// Test fixtures for version bumper workflow testing

export interface TestFixture {
  name: string;
  currentVersion: string;
  commits: string[];
  expectedVersion: string;
  expectedChangeType: "major" | "minor" | "patch" | "none";
  expectedChangelogContains: string[];
}

export const testFixtures: TestFixture[] = [
  {
    name: "patch-version-bump",
    currentVersion: "1.0.0",
    commits: ["fix: resolve memory leak in cache module"],
    expectedVersion: "1.0.1",
    expectedChangeType: "patch",
    expectedChangelogContains: ["1.0.1", "Bug Fixes", "memory leak"],
  },
  {
    name: "minor-version-bump",
    currentVersion: "1.0.0",
    commits: [
      "feat: add user authentication API",
      "feat: add session management",
    ],
    expectedVersion: "1.1.0",
    expectedChangeType: "minor",
    expectedChangelogContains: ["1.1.0", "Features", "authentication"],
  },
  {
    name: "major-version-bump",
    currentVersion: "2.5.3",
    commits: [
      "feat: redesign database schema\n\nBREAKING CHANGE: old column names deprecated",
      "fix: improve query performance",
    ],
    expectedVersion: "3.0.0",
    expectedChangeType: "major",
    expectedChangelogContains: ["3.0.0", "BREAKING CHANGES", "database schema"],
  },
  {
    name: "no-conventional-commits",
    currentVersion: "1.2.3",
    commits: ["Updated README", "fixed typo"],
    expectedVersion: "1.2.3",
    expectedChangeType: "none",
    expectedChangelogContains: [],
  },
  {
    name: "multiple-changes-prioritize-breaking",
    currentVersion: "0.1.0",
    commits: [
      "fix: minor bug fix",
      "feat: add feature",
      "feat!: breaking change API redesign",
    ],
    expectedVersion: "1.0.0",
    expectedChangeType: "major",
    expectedChangelogContains: ["1.0.0", "BREAKING CHANGES"],
  },
];

// Create mock git repos with test fixtures
export function createMockGitRepo(
  basePath: string,
  fixture: TestFixture
): void {
  const fs = require("fs");
  const path = require("path");

  // Create directory
  if (!fs.existsSync(basePath)) {
    fs.mkdirSync(basePath, { recursive: true });
  }

  // Initialize git repo
  const proc = Bun.spawnSync(["git", "init"], {
    cwd: basePath,
    stdio: ["ignore", "ignore", "ignore"],
  });

  if (!proc.success) {
    throw new Error("Failed to initialize git repo");
  }

  // Configure git
  Bun.spawnSync(["git", "config", "user.email", "test@example.com"], {
    cwd: basePath,
    stdio: ["ignore", "ignore", "ignore"],
  });
  Bun.spawnSync(["git", "config", "user.name", "Test User"], {
    cwd: basePath,
    stdio: ["ignore", "ignore", "ignore"],
  });

  // Create package.json with test version
  const pkgPath = path.join(basePath, "package.json");
  fs.writeFileSync(
    pkgPath,
    JSON.stringify({ version: fixture.currentVersion, name: "test-pkg" }, null, 2)
  );

  // Create initial commit
  Bun.spawnSync(["git", "add", "."], {
    cwd: basePath,
    stdio: ["ignore", "ignore", "ignore"],
  });
  Bun.spawnSync(["git", "commit", "-m", "initial commit"], {
    cwd: basePath,
    stdio: ["ignore", "ignore", "ignore"],
  });

  // Create test commits
  for (const commit of fixture.commits) {
    fs.writeFileSync(path.join(basePath, "TEMP.txt"), Math.random().toString());
    Bun.spawnSync(["git", "add", "."], {
      cwd: basePath,
      stdio: ["ignore", "ignore", "ignore"],
    });
    Bun.spawnSync(["git", "commit", "-m", commit], {
      cwd: basePath,
      stdio: ["ignore", "ignore", "ignore"],
    });
  }
}

export function cleanupMockRepo(basePath: string): void {
  const fs = require("fs");
  if (fs.existsSync(basePath)) {
    fs.rmSync(basePath, { recursive: true, force: true });
  }
}
