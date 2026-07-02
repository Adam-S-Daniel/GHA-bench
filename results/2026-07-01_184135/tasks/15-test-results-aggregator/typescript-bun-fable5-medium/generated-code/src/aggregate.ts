/**
 * Aggregation across matrix runs.
 *
 * Approach: walk every case from every file once, accumulating totals and a
 * per-test pass/fail tally keyed by "suite :: name". A test is flaky when it
 * both passed and failed at least once across the runs; skips are neutral.
 */
import type { AggregateSummary, FlakyTest, TestFileResult } from "./types";

/** Stable identifier for a test across runs. */
function testId(suite: string, name: string): string {
  return `${suite} :: ${name}`;
}

/**
 * Compute totals and flaky tests across all parsed result files.
 * The flaky list is sorted by id so output is deterministic.
 */
export function aggregate(files: TestFileResult[]): AggregateSummary {
  const summary: AggregateSummary = {
    total: 0,
    passed: 0,
    failed: 0,
    skipped: 0,
    durationSec: 0,
    files: files.length,
    flaky: [],
  };

  const tally = new Map<string, { passes: number; failures: number }>();

  for (const file of files) {
    for (const c of file.cases) {
      summary.total += 1;
      summary.durationSec += c.durationSec;
      if (c.status === "passed") summary.passed += 1;
      else if (c.status === "failed") summary.failed += 1;
      else summary.skipped += 1;

      if (c.status === "skipped") continue;
      const id = testId(c.suite, c.name);
      const entry = tally.get(id) ?? { passes: 0, failures: 0 };
      if (c.status === "passed") entry.passes += 1;
      else entry.failures += 1;
      tally.set(id, entry);
    }
  }

  const flaky: FlakyTest[] = [];
  for (const [id, { passes, failures }] of tally) {
    if (passes > 0 && failures > 0) flaky.push({ id, passes, failures });
  }
  flaky.sort((a, b) => a.id.localeCompare(b.id));
  summary.flaky = flaky;

  return summary;
}
