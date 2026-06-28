/**
 * Shared domain types for the test-results aggregator.
 *
 * The aggregator's pipeline is: parse (many files, many formats) -> a flat list
 * of `TestCase`s grouped into `TestRun`s -> aggregate into `AggregateResult` ->
 * render markdown. Keeping a single normalized `TestCase` shape lets every
 * downstream stage stay format-agnostic.
 */

/** Outcome of a single test case, normalized across all input formats. */
export type TestStatus = "passed" | "failed" | "skipped";

/** A single normalized test case from one run/file. */
export interface TestCase {
  /** Test name (e.g. the method/it name). */
  name: string;
  /** Owning suite/class name. Empty string when the format omits it. */
  suite: string;
  /** Normalized outcome. */
  status: TestStatus;
  /** Wall-clock duration of this case in seconds. */
  duration: number;
}

/**
 * The parsed contents of one result file. In a matrix build each file is one
 * matrix leg (e.g. ubuntu/node-20), so `name` identifies the leg.
 */
export interface TestRun {
  /** Identifier for this run — typically the source filename. */
  name: string;
  /** All test cases observed in this run. */
  cases: TestCase[];
}

/** Roll-up counts and timing across every run. */
export interface Totals {
  passed: number;
  failed: number;
  skipped: number;
  /** passed + failed + skipped. */
  total: number;
  /** Summed duration across all cases, in seconds. */
  duration: number;
}

/**
 * A test that did not produce a consistent outcome across runs: it passed in at
 * least one run and failed in at least one other. Skips are ignored for the
 * flaky determination (a skip is not evidence of pass or fail).
 */
export interface FlakyTest {
  /** Fully-qualified test identifier ("suite > name" or just "name"). */
  id: string;
  /** Number of runs in which it passed. */
  passed: number;
  /** Number of runs in which it failed. */
  failed: number;
}

/** The complete aggregation result, ready to render. */
export interface AggregateResult {
  totals: Totals;
  flaky: FlakyTest[];
  /** Number of result files/runs that were aggregated. */
  runCount: number;
}
