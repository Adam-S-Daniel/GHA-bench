// Shared domain types for the test results aggregator.

export interface TestCaseResult {
  name: string;
  suite: string;
  status: "passed" | "failed" | "skipped";
  duration: number; // seconds
  message?: string;
}

export interface ParsedFile {
  source: string; // file path this came from, used to identify a "run" in the matrix
  tests: TestCaseResult[];
}

export interface AggregateTotals {
  passed: number;
  failed: number;
  skipped: number;
  total: number;
  duration: number;
}

export interface FlakyTest {
  name: string;
  suite: string;
  outcomes: { source: string; status: TestCaseResult["status"] }[];
}

export interface AggregateResult {
  totals: AggregateTotals;
  flakyTests: FlakyTest[];
  files: ParsedFile[];
}
