/**
 * Shared domain types for the test-results aggregator.
 *
 * These types are the common, format-agnostic representation that every
 * parser (JUnit XML, JSON, ...) normalises into. Keeping a single internal
 * shape means the aggregator and markdown renderer never need to know which
 * file format a result originally came from.
 */

/** The outcome of a single test case. */
export type TestStatus = "passed" | "failed" | "skipped";

/** A single normalised test case from one test run. */
export interface TestCase {
  /** Test name (e.g. "test_divides_two_numbers"). */
  name: string;
  /** Optional suite/class grouping (e.g. "MathSuite"). */
  suite?: string;
  /** Outcome of the test. */
  status: TestStatus;
  /** Execution time in seconds. Defaults to 0 when a format omits it. */
  duration: number;
  /** Failure/error message, when the test did not pass. */
  message?: string;
}

/**
 * A single test run, typically one file produced by one leg of a CI matrix
 * (e.g. one OS/runtime combination).
 */
export interface TestRun {
  /** A label identifying the run — usually the source file name. */
  source: string;
  /** All test cases observed in this run. */
  cases: TestCase[];
}

/** Aggregated counts across every run. */
export interface Totals {
  passed: number;
  failed: number;
  skipped: number;
  /** passed + failed + skipped (every executed/observed case). */
  total: number;
  /** Sum of every case's duration, in seconds. */
  duration: number;
}

/**
 * A test that did not produce a consistent result across runs — it passed in
 * at least one run and failed in at least one other. Skips do not count as
 * either pass or fail for flakiness purposes.
 */
export interface FlakyTest {
  /** Stable identity of the test ("suite > name", or just "name"). */
  key: string;
  /** Number of runs in which the test passed. */
  passed: number;
  /** Number of runs in which the test failed. */
  failed: number;
}

/** The full aggregation result the renderer consumes. */
export interface Aggregate {
  /** Number of runs (files) that were aggregated. */
  runCount: number;
  totals: Totals;
  /** Flaky tests, sorted by key for deterministic output. */
  flaky: FlakyTest[];
}
