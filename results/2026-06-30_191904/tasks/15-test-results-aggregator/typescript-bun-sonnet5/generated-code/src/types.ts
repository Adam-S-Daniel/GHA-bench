/** Possible outcomes for an individual test case. */
export type TestStatus = "passed" | "failed" | "skipped";

/** A single test case result, normalized from either JUnit XML or JSON input. */
export interface TestCase {
  name: string;
  classname: string;
  status: TestStatus;
  duration: number; // seconds
  message?: string; // failure/error message, present when status === "failed"
}

/** A parsed suite of test cases from a single result file (one "run" in a matrix build). */
export interface TestSuiteResult {
  suiteName: string;
  source: string; // file path this suite was parsed from
  tests: TestCase[];
}

/** One run's outcome for a test that produced different outcomes across runs. */
export interface FlakyOutcome {
  source: string;
  status: TestStatus;
}

/** A test that passed in some runs and failed in others (identified across suites). */
export interface FlakyTest {
  suiteName: string;
  classname: string;
  name: string;
  outcomes: FlakyOutcome[];
  passCount: number;
  failCount: number;
}

/** Totals and derived data after aggregating one or more TestSuiteResults. */
export interface AggregatedResults {
  totalTests: number;
  passed: number;
  failed: number;
  skipped: number;
  totalDuration: number;
  suites: TestSuiteResult[];
  flakyTests: FlakyTest[];
}
