// Aggregates parsed test result files (e.g. one per matrix build leg) into
// overall totals and a list of flaky tests (same suite/name, differing status
// across files).

import type { AggregateResult, FlakyTest, ParsedFile, Totals } from "./types";

function computeTotals(files: ParsedFile[]): Totals {
  const totals: Totals = { total: 0, passed: 0, failed: 0, skipped: 0, duration: 0 };
  for (const file of files) {
    for (const test of file.tests) {
      totals.total += 1;
      totals[test.status] += 1;
      totals.duration += test.duration;
    }
  }
  return totals;
}

function findFlakyTests(files: ParsedFile[]): FlakyTest[] {
  // Key by suite+name so identically-named tests in different suites don't collide.
  const bySuiteAndName = new Map<string, FlakyTest>();

  for (const file of files) {
    for (const test of file.tests) {
      const key = `${test.suite}::${test.name}`;
      let entry = bySuiteAndName.get(key);
      if (!entry) {
        entry = { suite: test.suite, name: test.name, outcomes: [] };
        bySuiteAndName.set(key, entry);
      }
      entry.outcomes.push({ source: file.source, status: test.status });
    }
  }

  const flaky: FlakyTest[] = [];
  for (const entry of bySuiteAndName.values()) {
    const distinctStatuses = new Set(entry.outcomes.map((o) => o.status));
    if (distinctStatuses.size > 1) {
      flaky.push(entry);
    }
  }
  return flaky;
}

export function aggregate(files: ParsedFile[]): AggregateResult {
  if (files.length === 0) {
    throw new Error("aggregate() requires at least one parsed file");
  }

  return {
    files,
    totals: computeTotals(files),
    flakyTests: findFlakyTests(files),
  };
}
