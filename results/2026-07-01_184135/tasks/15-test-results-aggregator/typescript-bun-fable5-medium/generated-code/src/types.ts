/**
 * Shared type contract for the test-results aggregator.
 *
 * Every parser (JUnit XML, JSON) normalizes its input into `TestFileResult`,
 * so aggregation and reporting are format-agnostic.
 */

/** Outcome of a single test case in a single run. */
export type TestStatus = "passed" | "failed" | "skipped";

/** One test case result from one result file. */
export interface TestCaseResult {
  /** Suite / classname the test belongs to. */
  suite: string;
  /** Test case name. */
  name: string;
  status: TestStatus;
  /** Duration in seconds (0 when the format omits it). */
  durationSec: number;
  /** Failure message, when status is "failed". */
  message?: string;
}

/** All test cases parsed from a single result file (= one matrix run). */
export interface TestFileResult {
  /** Where the results came from, e.g. a file path or matrix job label. */
  source: string;
  cases: TestCaseResult[];
}

/** A test that passed in some runs and failed in others. */
export interface FlakyTest {
  /** "suite :: name" identifier. */
  id: string;
  passes: number;
  failures: number;
}

/** Aggregated totals across all parsed result files. */
export interface AggregateSummary {
  total: number;
  passed: number;
  failed: number;
  skipped: number;
  durationSec: number;
  /** Number of result files aggregated. */
  files: number;
  flaky: FlakyTest[];
}
