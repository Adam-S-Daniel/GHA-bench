// Aggregation logic: fold many parsed result files into one rolled-up view.
//
// This is where the "matrix build" simulation happens — each ParsedFile is one
// shard of the matrix, and we combine them to answer:
//   * How many tests passed / failed / skipped overall? (totals)
//   * Which tests are *flaky* — i.e. produced different outcomes across shards?

import type {
  Aggregation,
  FlakyTest,
  ParsedFile,
  Totals,
} from "./types.ts";

/** Stable identity for a test across runs: suite + name. */
function testId(suite: string, name: string): string {
  return `${suite} > ${name}`;
}

/**
 * Aggregate parsed files into totals and a flaky-test report.
 *
 * Flakiness is defined as: across all runs of a given test (keyed by
 * suite+name), it both passed at least once AND failed at least once. Skips
 * alone never make a test flaky.
 */
export function aggregate(files: ParsedFile[]): Aggregation {
  const totals: Totals = {
    passed: 0,
    failed: 0,
    skipped: 0,
    total: 0,
    duration: 0,
  };

  // Per-test outcome tallies, keyed by stable test id.
  const tally = new Map<
    string,
    { suite: string; name: string; passed: number; failed: number; skipped: number }
  >();

  for (const f of files) {
    for (const r of f.results) {
      totals[r.status]++;
      totals.total++;
      totals.duration += r.duration;

      const id = testId(r.suite, r.name);
      let entry = tally.get(id);
      if (!entry) {
        entry = { suite: r.suite, name: r.name, passed: 0, failed: 0, skipped: 0 };
        tally.set(id, entry);
      }
      entry[r.status]++;
    }
  }

  // A test is flaky iff it has both at least one pass and at least one fail.
  const flaky: FlakyTest[] = [];
  for (const [id, e] of tally) {
    if (e.passed > 0 && e.failed > 0) {
      flaky.push({
        id,
        suite: e.suite,
        name: e.name,
        passed: e.passed,
        failed: e.failed,
        skipped: e.skipped,
      });
    }
  }

  // Most-failing tests first; tie-break on id for deterministic output.
  flaky.sort((a, b) => b.failed - a.failed || a.id.localeCompare(b.id));

  return { totals, flaky, fileCount: files.length };
}
