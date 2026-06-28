/**
 * Shared type definitions for the test-results aggregator.
 *
 * Two on-disk formats (JUnit XML and JSON) are normalised into the same
 * internal model (`TestRun` / `TestCaseResult`) so the aggregation, flaky
 * detection, and markdown rendering layers never have to care which format a
 * result originally came from.
 */

/**
 * The normalised outcome of a single test. JUnit's `<error>` is folded into
 * `failed` (an errored test did not pass), and the JSON format's various
 * spellings ("fail", "error", ...) normalise here too. Keeping the normalised
 * status set this small keeps flaky detection unambiguous: a test is flaky when
 * it is sometimes `passed` and sometimes `failed`.
 */
export type TestStatus = "passed" | "failed" | "skipped";

/** A single normalised test case from one run. */
export interface TestCaseResult {
  /** The test's own name (the JUnit `name` attr or the JSON `name` field). */
  name: string;
  /** Owning suite/class. Falls back to "" when the source provides none. */
  suite: string;
  /** Normalised outcome. */
  status: TestStatus;
  /** Execution time in seconds (0 when the source omits it). */
  durationSeconds: number;
  /** Optional failure/error message, when the source provides one. */
  message?: string;
}

/**
 * One result file == one "run" (one leg of a matrix build). `source` is the
 * file path or other identifier the run came from, used in error messages and
 * the markdown breakdown.
 */
export interface TestRun {
  /** Identifier for this run (typically the file path). */
  source: string;
  /** Optional human-readable run/suite name from the file. */
  name: string;
  /** All test cases recorded in this run. */
  cases: TestCaseResult[];
}

/** Aggregate totals across every run. */
export interface Totals {
  passed: number;
  failed: number;
  skipped: number;
  /** passed + failed + skipped, i.e. total test executions across all runs. */
  total: number;
  /** Sum of every case's duration, in seconds. */
  durationSeconds: number;
}

/**
 * A test that did not produce a consistent verdict across the runs it appeared
 * in: it passed at least once and failed at least once. This is the classic
 * "flaky" signal for a matrix build.
 */
export interface FlakyTest {
  /** Stable identity used to correlate the test across runs (`suite::name`). */
  key: string;
  name: string;
  suite: string;
  /** Number of runs in which this test passed. */
  passed: number;
  /** Number of runs in which this test failed. */
  failed: number;
  /** Number of runs in which this test was skipped. */
  skipped: number;
  /** Total number of runs this test appeared in. */
  appearances: number;
}

/** The full aggregation result handed to the renderer. */
export interface AggregateResult {
  totals: Totals;
  /** Flaky tests, sorted most-failed-first then by name for determinism. */
  flaky: FlakyTest[];
  /** Number of result files / runs aggregated. */
  runCount: number;
  /** Per-run summary, in input order, for the markdown breakdown. */
  runs: RunSummary[];
  /** Overall verdict: true when there were zero failures. */
  passed: boolean;
}

/** Compact per-run summary used in the markdown "per run" table. */
export interface RunSummary {
  source: string;
  name: string;
  passed: number;
  failed: number;
  skipped: number;
  durationSeconds: number;
}
