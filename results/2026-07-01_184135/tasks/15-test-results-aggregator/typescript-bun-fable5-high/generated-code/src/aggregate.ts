/**
 * Aggregation across matrix runs.
 *
 * Approach: a test's identity across runs is `suite > name`. We bucket every
 * occurrence of an identity across all runs, then classify:
 *   - flaky:  passed in at least one run AND failed in at least one run
 *   - failed: failed in at least one run and never passed (a real failure)
 * Skips never affect flakiness — skipped-then-passed is normal matrix
 * behavior (e.g. platform-conditional tests), not a flake.
 */
import type { AggregateReport, FailedTest, FlakyTest, TestRun, Totals } from "./types";

/** Round to milliseconds so summed float durations stay presentable. */
function roundDuration(seconds: number): number {
  return Math.round(seconds * 1000) / 1000;
}

function totalsOf(runs: TestRun[]): Totals {
  const totals: Totals = { total: 0, passed: 0, failed: 0, skipped: 0, durationSeconds: 0 };
  for (const run of runs) {
    for (const c of run.cases) {
      totals.total += 1;
      totals[c.status] += 1;
      totals.durationSeconds += c.durationSeconds;
    }
  }
  totals.durationSeconds = roundDuration(totals.durationSeconds);
  return totals;
}

/** Every run a given test identity appeared in, grouped by outcome. */
interface Occurrences {
  passedIn: string[];
  failedIn: string[];
  firstFailureMessage?: string;
}

export function aggregate(runs: TestRun[]): AggregateReport {
  if (runs.length === 0) {
    throw new Error("aggregate: no test runs to aggregate — were any result files found?");
  }

  // Bucket occurrences by test identity, preserving first-seen order so the
  // report is stable across invocations.
  const byId = new Map<string, Occurrences>();
  for (const run of runs) {
    for (const c of run.cases) {
      const id = `${c.suite} > ${c.name}`;
      let occ = byId.get(id);
      if (!occ) {
        occ = { passedIn: [], failedIn: [] };
        byId.set(id, occ);
      }
      if (c.status === "passed") occ.passedIn.push(run.source);
      if (c.status === "failed") {
        occ.failedIn.push(run.source);
        if (occ.firstFailureMessage === undefined && c.message !== undefined) {
          occ.firstFailureMessage = c.message;
        }
      }
    }
  }

  const flaky: FlakyTest[] = [];
  const failed: FailedTest[] = [];
  for (const [id, occ] of byId) {
    if (occ.failedIn.length === 0) continue;
    if (occ.passedIn.length > 0) {
      flaky.push({ id, passedIn: occ.passedIn, failedIn: occ.failedIn });
    } else {
      failed.push({
        id,
        failedIn: occ.failedIn,
        ...(occ.firstFailureMessage !== undefined ? { message: occ.firstFailureMessage } : {}),
      });
    }
  }

  return {
    totals: totalsOf(runs),
    perRun: runs.map((run) => ({ source: run.source, totals: totalsOf([run]) })),
    flaky,
    failed,
  };
}
