import type { AggregatedResults, FlakyTest, TestSuiteResult } from "./types";

/** Identity used to correlate the "same" test across multiple runs/files. */
function testKey(suiteName: string, classname: string, name: string): string {
  return `${suiteName}::${classname}::${name}`;
}

/**
 * Aggregates one or more parsed test suites (e.g. one per matrix job) into
 * overall totals and a list of flaky tests -- tests that produced both a
 * "passed" and a "failed" outcome across the runs.
 */
export function aggregate(suites: TestSuiteResult[]): AggregatedResults {
  let passed = 0;
  let failed = 0;
  let skipped = 0;
  let totalDuration = 0;

  const bySameTest = new Map<
    string,
    { suiteName: string; classname: string; name: string; outcomes: { source: string; status: string }[] }
  >();

  for (const suite of suites) {
    for (const test of suite.tests) {
      if (test.status === "passed") passed++;
      else if (test.status === "failed") failed++;
      else skipped++;

      totalDuration += test.duration;

      const key = testKey(suite.suiteName, test.classname, test.name);
      const existing = bySameTest.get(key);
      const outcome = { source: suite.source, status: test.status };
      if (existing) {
        existing.outcomes.push(outcome);
      } else {
        bySameTest.set(key, {
          suiteName: suite.suiteName,
          classname: test.classname,
          name: test.name,
          outcomes: [outcome],
        });
      }
    }
  }

  const flakyTests: FlakyTest[] = [];
  for (const entry of bySameTest.values()) {
    const passCount = entry.outcomes.filter((o) => o.status === "passed").length;
    const failCount = entry.outcomes.filter((o) => o.status === "failed").length;
    if (passCount > 0 && failCount > 0) {
      flakyTests.push({
        suiteName: entry.suiteName,
        classname: entry.classname,
        name: entry.name,
        outcomes: entry.outcomes as FlakyTest["outcomes"],
        passCount,
        failCount,
      });
    }
  }

  const totalTests = passed + failed + skipped;

  return { totalTests, passed, failed, skipped, totalDuration, suites, flakyTests };
}
