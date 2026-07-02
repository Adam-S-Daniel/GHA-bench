/**
 * Shared domain types for the test-results aggregator.
 *
 * The pipeline is:  raw result file --parse--> TestRun --aggregate--> AggregateReport --render--> markdown
 */

/** Outcome of a single test case in a single run. */
export type TestStatus = "passed" | "failed" | "skipped";

/** One executed test case from one result file. */
export interface TestCaseResult {
  /** Suite / classname grouping (e.g. JUnit `classname` attribute). */
  suite: string;
  /** Test name (e.g. JUnit `name` attribute). */
  name: string;
  status: TestStatus;
  /** Wall-clock duration in seconds. */
  durationSeconds: number;
  /** Failure message, when status === "failed" and one was provided. */
  message?: string;
}

/** All test cases parsed from one result file (one matrix job's output). */
export interface TestRun {
  /** Label for the run — the source file name (matrix shard identifier). */
  source: string;
  cases: TestCaseResult[];
}

/** Per-status totals across every aggregated run. */
export interface Totals {
  total: number;
  passed: number;
  failed: number;
  skipped: number;
  durationSeconds: number;
}

/** A test that both passed and failed across different runs of the same matrix build. */
export interface FlakyTest {
  /** Stable identity: `suite > name`. */
  id: string;
  /** Sources (files) in which the test passed. */
  passedIn: string[];
  /** Sources (files) in which the test failed. */
  failedIn: string[];
}

/** A test that failed and never passed in any run (a "real" failure, not flake). */
export interface FailedTest {
  id: string;
  failedIn: string[];
  /** First failure message encountered, if any. */
  message?: string;
}

/** The full aggregation result across all runs. */
export interface AggregateReport {
  totals: Totals;
  perRun: { source: string; totals: Totals }[];
  flaky: FlakyTest[];
  failed: FailedTest[];
}
