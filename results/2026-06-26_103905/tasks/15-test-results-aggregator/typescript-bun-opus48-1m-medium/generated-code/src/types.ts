// Shared domain types for the test-results aggregator.
//
// A "test result" is a single execution of a single test case. Many of these
// are collected across multiple result files (each file = one matrix-build
// shard) and then aggregated.

/** The three terminal states a test case can be in. */
export type TestStatus = "passed" | "failed" | "skipped";

/**
 * One execution of one test case, normalized from whatever input format it
 * came from (JUnit XML or our JSON schema).
 */
export interface TestResult {
  /** Test case name, e.g. "handles empty input". */
  name: string;
  /** Owning suite / class, e.g. "MathTest". Empty string if unknown. */
  suite: string;
  /** Terminal status of this execution. */
  status: TestStatus;
  /** Wall-clock duration of this execution, in seconds. */
  duration: number;
  /** Optional human-facing failure message (present for failures). */
  message?: string;
}

/**
 * The fully-typed contents of a single parsed result file: a flat list of
 * test executions plus the source filename for diagnostics.
 */
export interface ParsedFile {
  /** Source file path the results were parsed from. */
  source: string;
  /** Every test execution found in the file. */
  results: TestResult[];
}

/** Aggregate counters computed across all parsed files. */
export interface Totals {
  passed: number;
  failed: number;
  skipped: number;
  /** Total number of test executions (passed + failed + skipped). */
  total: number;
  /** Summed duration across every execution, in seconds. */
  duration: number;
}

/**
 * A test that produced inconsistent outcomes across runs — passing at least
 * once and failing at least once. The canonical signal of flakiness.
 */
export interface FlakyTest {
  /** Fully-qualified id, "suite > name". */
  id: string;
  suite: string;
  name: string;
  passed: number;
  failed: number;
  skipped: number;
}

/** The complete aggregation result returned by the aggregator. */
export interface Aggregation {
  totals: Totals;
  flaky: FlakyTest[];
  /** Total number of distinct result files aggregated. */
  fileCount: number;
}
