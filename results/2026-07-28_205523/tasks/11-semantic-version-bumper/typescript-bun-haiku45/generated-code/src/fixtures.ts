// Test fixtures for semantic version bumper
import type { Commit } from "./commits";

// Test case: simple patch update (fix only)
export const patchFixtureCommits: Commit[] = [
  {
    hash: "a1b2c3d4e5f6g7h8",
    message: "fix: resolve database connection timeout",
    body: "Increased timeout to 30 seconds and added retry logic",
  },
];

// Test case: minor update (feat only)
export const minorFixtureCommits: Commit[] = [
  {
    hash: "i1j2k3l4m5n6o7p8",
    message: "feat: add user authentication system",
    body: "Implemented JWT-based authentication with refresh tokens",
  },
];

// Test case: major update (breaking change)
export const majorFixtureCommits: Commit[] = [
  {
    hash: "q1r2s3t4u5v6w7x8",
    message: "feat!: redesign API endpoints",
    body: "BREAKING CHANGE: All old endpoints removed\nPlease use new v2 API",
  },
];

// Test case: mixed commits
export const mixedFixtureCommits: Commit[] = [
  {
    hash: "abc1234567890fed",
    message: "feat: add export to CSV feature",
    body: "Users can now export reports to CSV format",
  },
  {
    hash: "def2345678901abc",
    message: "fix: correct calculation in monthly report",
    body: "Revenue calculation had off-by-one error",
  },
  {
    hash: "ghi3456789012def",
    message: "docs: update API documentation",
    body: "Added examples for new endpoints",
  },
  {
    hash: "jkl4567890123ghi",
    message: "fix: prevent duplicate entries in database",
    body: "Added unique constraint to user email field",
  },
];

// Test case: breaking change in body
export const breakingChangeInBodyCommits: Commit[] = [
  {
    hash: "mno5678901234jkl",
    message: "feat: complete permission system refactor",
    body: "BREAKING CHANGE: Permission model completely redesigned\nOld permission checks will fail, use new API",
  },
];

// Test case: multiple breaking changes
export const multipleBreakingChangesCommits: Commit[] = [
  {
    hash: "pqr6789012345mno",
    message: "feat!: upgrade database schema",
    body: "Major schema changes, migrations required",
  },
  {
    hash: "stu7890123456pqr",
    message: "feat: add new caching layer",
    body: "Non-breaking feature addition",
  },
  {
    hash: "vwx8901234567stu",
    message: "fix!: change authentication flow",
    body: "BREAKING CHANGE: OAuth2 flow changed",
  },
];

// Test case: empty commits
export const emptyFixtureCommits: Commit[] = [];

// Export test scenarios
export const testScenarios = {
  patch: {
    name: "Patch Update (fix only)",
    currentVersion: "1.0.0",
    expectedVersion: "1.0.1",
    commits: patchFixtureCommits,
  },
  minor: {
    name: "Minor Update (feat only)",
    currentVersion: "1.0.0",
    expectedVersion: "1.1.0",
    commits: minorFixtureCommits,
  },
  major: {
    name: "Major Update (breaking change)",
    currentVersion: "1.0.0",
    expectedVersion: "2.0.0",
    commits: majorFixtureCommits,
  },
  mixed: {
    name: "Mixed Commits",
    currentVersion: "1.2.3",
    expectedVersion: "1.3.0",
    commits: mixedFixtureCommits,
  },
  breakingInBody: {
    name: "Breaking Change in Body",
    currentVersion: "2.1.0",
    expectedVersion: "3.0.0",
    commits: breakingChangeInBodyCommits,
  },
  multipleBreaking: {
    name: "Multiple Breaking Changes",
    currentVersion: "1.5.2",
    expectedVersion: "2.0.0",
    commits: multipleBreakingChangesCommits,
  },
  empty: {
    name: "No Commits",
    currentVersion: "1.0.0",
    expectedVersion: "1.0.0",
    commits: emptyFixtureCommits,
  },
};
