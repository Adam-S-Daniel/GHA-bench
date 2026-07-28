// Mock commit fixtures for testing
export const mockCommitFixtures = {
  // Scenario 1: simple patch (only fixes)
  patchOnly: ["fix: correct typo in docs", "fix: handle null pointer"],

  // Scenario 2: simple minor (feature + fixes)
  minorUpdate: [
    "feat: add user authentication",
    "fix: improve error handling",
    "fix: memory leak in cache",
  ],

  // Scenario 3: major (breaking change)
  majorUpdate: [
    "feat!: redesign API endpoints",
    "feat: add new auth method",
    "fix: resolve race condition",
  ],

  // Scenario 4: breaking change with BREAKING CHANGE footer
  breakingFooter: [
    "refactor: rewrite database layer\n\nBREAKING CHANGE: old database API no longer supported",
    "feat: add new query interface",
  ],

  // Scenario 5: empty (no version bump needed)
  empty: [],
};

export const testVersions = {
  initial: { major: 1, minor: 0, patch: 0 },
  nextPatch: { major: 1, minor: 0, patch: 1 },
  nextMinor: { major: 1, minor: 1, patch: 0 },
  nextMajor: { major: 2, minor: 0, patch: 0 },
};
