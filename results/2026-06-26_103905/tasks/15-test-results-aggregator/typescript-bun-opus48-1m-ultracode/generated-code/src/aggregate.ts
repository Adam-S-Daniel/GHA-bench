/**
 * Aggregation layer. Given the normalised runs from the parsers, compute the
 * matrix-wide totals and identify flaky tests.
 *
 * Flaky == a test that passed in at least one run and failed in at least one
 * other run. Skips never make a test flaky on their own; flakiness is strictly
 * about an inconsistent pass/fail verdict.
 */
import type { AggregateResult, FlakyTest, RunSummary, TestRun } from "./types";

/**
 * Round to milliseconds. Summing floating-point seconds accumulates tiny
 * representation errors (0.1 + 0.2 === 0.30000000000000004); rounding the
 * accumulated totals to 3 decimals keeps the reported numbers clean and
 * deterministic without affecting any real-world precision.
 */
function roundMillis(seconds: number): number {
  return Math.round(seconds * 1000) / 1000;
}

/** Stable cross-run identity for a test case. */
function testKey(suite: string, name: string): string {
  return `${suite}::${name}`;
}

/** Per-test tally accumulated while scanning every run. */
interface Tally {
  name: string;
  suite: string;
  passed: number;
  failed: number;
  skipped: number;
  appearances: number;
}

/**
 * Aggregate the supplied runs. Returns matrix-wide totals, the flaky-test list
 * (sorted most-failures-first, then by key for stable output), a per-run
 * summary in input order, and the overall pass/fail verdict.
 */
export function aggregate(runs: TestRun[]): AggregateResult {
  let passed = 0;
  let failed = 0;
  let skipped = 0;
  let total = 0;
  let durationSeconds = 0;

  const tallies = new Map<string, Tally>();
  const runSummaries: RunSummary[] = [];

  for (const r of runs) {
    let runPassed = 0;
    let runFailed = 0;
    let runSkipped = 0;
    let runDuration = 0;

    for (const c of r.cases) {
      total++;
      durationSeconds += c.durationSeconds;
      runDuration += c.durationSeconds;

      if (c.status === "passed") {
        passed++;
        runPassed++;
      } else if (c.status === "failed") {
        failed++;
        runFailed++;
      } else {
        skipped++;
        runSkipped++;
      }

      const key = testKey(c.suite, c.name);
      let tally = tallies.get(key);
      if (!tally) {
        tally = { name: c.name, suite: c.suite, passed: 0, failed: 0, skipped: 0, appearances: 0 };
        tallies.set(key, tally);
      }
      tally.appearances++;
      if (c.status === "passed") tally.passed++;
      else if (c.status === "failed") tally.failed++;
      else tally.skipped++;
    }

    runSummaries.push({
      source: r.source,
      name: r.name,
      passed: runPassed,
      failed: runFailed,
      skipped: runSkipped,
      durationSeconds: roundMillis(runDuration),
    });
  }

  const flaky: FlakyTest[] = [];
  for (const [key, tally] of tallies) {
    // The defining condition: passed somewhere AND failed somewhere.
    if (tally.passed > 0 && tally.failed > 0) {
      flaky.push({
        key,
        name: tally.name,
        suite: tally.suite,
        passed: tally.passed,
        failed: tally.failed,
        skipped: tally.skipped,
        appearances: tally.appearances,
      });
    }
  }
  // Most-failing tests first; ties broken by key. Use a raw codepoint compare
  // (not localeCompare) so the ordering is deterministic regardless of the
  // host locale/ICU data — important for reproducible CI output.
  flaky.sort((a, b) => b.failed - a.failed || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));

  return {
    totals: {
      passed,
      failed,
      skipped,
      total,
      durationSeconds: roundMillis(durationSeconds),
    },
    flaky,
    runCount: runs.length,
    runs: runSummaries,
    passed: failed === 0,
  };
}
