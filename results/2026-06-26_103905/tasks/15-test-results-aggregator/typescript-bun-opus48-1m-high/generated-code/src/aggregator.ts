/**
 * Aggregation: combine many `TestRun`s (one per matrix leg) into roll-up
 * totals plus a flaky-test report.
 *
 * Totals are a straight sum over every case in every run. Flakiness is decided
 * per logical test identity ("suite > name"): a test is flaky when, across the
 * runs, it both passed at least once AND failed at least once. Skips are not
 * evidence either way and are ignored for the flaky decision (though they still
 * count toward the skipped total).
 */

import type {
  AggregateResult,
  FlakyTest,
  TestRun,
  Totals,
} from "./types.ts";

/** Stable identity for a test across runs. */
function testId(suite: string, name: string): string {
  return suite ? `${suite} > ${name}` : name;
}

/** Per-test tally accumulated while scanning every run. */
interface Tally {
  passed: number;
  failed: number;
}

export function aggregate(runs: TestRun[]): AggregateResult {
  const totals: Totals = {
    passed: 0,
    failed: 0,
    skipped: 0,
    total: 0,
    duration: 0,
  };

  // Per logical test, count how many runs passed vs failed it. Insertion order
  // is preserved by Map so ties in the final sort stay deterministic.
  const tallies = new Map<string, Tally>();

  for (const run of runs) {
    for (const c of run.cases) {
      totals.total += 1;
      totals.duration += c.duration;

      switch (c.status) {
        case "passed":
          totals.passed += 1;
          break;
        case "failed":
          totals.failed += 1;
          break;
        case "skipped":
          totals.skipped += 1;
          break;
      }

      // Skips don't inform flakiness, so don't tally them.
      if (c.status === "skipped") continue;

      const id = testId(c.suite, c.name);
      const tally = tallies.get(id) ?? { passed: 0, failed: 0 };
      if (c.status === "passed") tally.passed += 1;
      else tally.failed += 1;
      tallies.set(id, tally);
    }
  }

  // A test is flaky iff it has both at least one pass and at least one fail.
  const flaky: FlakyTest[] = [];
  for (const [id, tally] of tallies) {
    if (tally.passed > 0 && tally.failed > 0) {
      flaky.push({ id, passed: tally.passed, failed: tally.failed });
    }
  }

  // Most-failing first; ties broken by total runs, then id for stability.
  flaky.sort((a, b) => {
    if (b.failed !== a.failed) return b.failed - a.failed;
    const aTotal = a.passed + a.failed;
    const bTotal = b.passed + b.failed;
    if (bTotal !== aTotal) return bTotal - aTotal;
    return a.id.localeCompare(b.id);
  });

  return { totals, flaky, runCount: runs.length };
}
