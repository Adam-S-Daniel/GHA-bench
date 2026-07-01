import type { AggregateResult, FlakyTest, ParsedFile } from "./types";

// Combines all test cases (identified by "suite/name") across every parsed
// file into a per-test list of outcomes, so we can compute totals and detect
// flakiness (tests whose status differs between runs) in one pass.

export function aggregate(files: ParsedFile[]): AggregateResult {
  const totals = { passed: 0, failed: 0, skipped: 0, total: 0, duration: 0 };
  const outcomesByTest = new Map<string, FlakyTest>();

  for (const file of files) {
    for (const test of file.tests) {
      totals[test.status]++;
      totals.total++;
      totals.duration += test.duration;

      const key = `${test.suite}/${test.name}`;
      const entry = outcomesByTest.get(key) ?? { name: test.name, suite: test.suite, outcomes: [] };
      entry.outcomes.push({ source: file.source, status: test.status });
      outcomesByTest.set(key, entry);
    }
  }

  const flakyTests = [...outcomesByTest.values()].filter((entry) => {
    const statuses = new Set(entry.outcomes.map((o) => o.status));
    return statuses.has("passed") && statuses.has("failed");
  });

  return { totals, flakyTests, files };
}
