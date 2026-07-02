// Shared type definitions for the test-results-aggregator.

/** Normalized status of a single test case, regardless of source format. */
export type TestStatus = "passed" | "failed" | "skipped";

/** A single test case, normalized from either JUnit XML or JSON input. */
export interface TestCase {
  /** Test name (e.g. "should add two numbers"). */
  name: string;
  /** Suite / class the test belongs to (e.g. "MathUtils"). */
  suite: string;
  status: TestStatus;
  /** Duration in seconds. */
  duration: number;
  /** Failure message, only present when status is "failed". */
  message?: string;
}

/** One parsed input file, tagged with where it came from (for flaky detection across matrix runs). */
export interface ParsedFile {
  /** Path or label identifying this run, e.g. "run-ubuntu-node18.xml". */
  source: string;
  format: "junit" | "json";
  tests: TestCase[];
}

export interface Totals {
  total: number;
  passed: number;
  failed: number;
  skipped: number;
  /** Total duration in seconds across all tests. */
  duration: number;
}

/** A test whose status differs across two or more source files (passed in some runs, failed in others). */
export interface FlakyTest {
  suite: string;
  name: string;
  outcomes: Array<{ source: string; status: TestStatus }>;
}

export interface AggregateResult {
  files: ParsedFile[];
  totals: Totals;
  flakyTests: FlakyTest[];
}
