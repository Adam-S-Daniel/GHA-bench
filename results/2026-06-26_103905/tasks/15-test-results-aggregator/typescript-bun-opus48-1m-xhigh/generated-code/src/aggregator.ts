/**
 * Aggregation logic: fold many {@link TestRun}s (one per CI-matrix leg) into a
 * single {@link Aggregate} of totals plus flaky-test detection.
 */
import type { Aggregate, FlakyTest, TestCase, TestRun, Totals } from "./types.ts";

/**
 * Stable identity for a test across runs. We combine suite + name so that two
 * tests with the same short name in different suites are not conflated.
 */
export function testKey(testCase: Pick<TestCase, "name" | "suite">): string {
  return testCase.suite ? `${testCase.suite} > ${testCase.name}` : testCase.name;
}

/** Per-test pass/fail tally used internally to decide flakiness. */
interface Tally {
  passed: number;
  failed: number;
}

/**
 * Aggregate runs into totals and a flaky-test list.
 *
 * A test is "flaky" when, across all runs, it both passed at least once and
 * failed at least once. Skipped outcomes are ignored for flakiness (a test
 * that is skipped in one run and passes in another is not flaky).
 */
export function aggregate(runs: TestRun[]): Aggregate {
  const totals: Totals = { passed: 0, failed: 0, skipped: 0, total: 0, duration: 0 };
  const tallies = new Map<string, Tally>();

  for (const run of runs) {
    for (const c of run.cases) {
      // Roll the case into the global totals.
      totals.total += 1;
      totals.duration += c.duration;
      if (c.status === "passed") totals.passed += 1;
      else if (c.status === "failed") totals.failed += 1;
      else totals.skipped += 1;

      // Track per-test pass/fail counts for flaky detection.
      const key = testKey(c);
      const tally = tallies.get(key) ?? { passed: 0, failed: 0 };
      if (c.status === "passed") tally.passed += 1;
      else if (c.status === "failed") tally.failed += 1;
      tallies.set(key, tally);
    }
  }

  const flaky: FlakyTest[] = [];
  for (const [key, tally] of tallies) {
    if (tally.passed > 0 && tally.failed > 0) {
      flaky.push({ key, passed: tally.passed, failed: tally.failed });
    }
  }
  // Deterministic ordering makes the markdown output stable and assertable.
  flaky.sort((a, b) => a.key.localeCompare(b.key));

  return { runCount: runs.length, totals, flaky };
}
