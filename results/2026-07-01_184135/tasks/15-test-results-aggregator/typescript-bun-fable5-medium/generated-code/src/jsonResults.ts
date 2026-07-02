/**
 * JSON results parser.
 *
 * Accepts either a single suite:
 *   { "suite": "api", "tests": [ { "name", "status", "duration"?, "message"? } ] }
 * or a multi-suite wrapper:
 *   { "suites": [ <single suite>, ... ] }
 *
 * Everything is validated explicitly so a malformed file produces an error
 * that names the file and the offending field instead of a vague crash.
 */
import type { TestCaseResult, TestFileResult, TestStatus } from "./types";

const VALID_STATUSES: ReadonlySet<string> = new Set([
  "passed",
  "failed",
  "skipped",
]);

interface JsonTest {
  name: string;
  status: string;
  duration?: number;
  message?: string;
}

interface JsonSuite {
  suite: string;
  tests: JsonTest[];
}

function isJsonSuite(value: unknown): value is JsonSuite {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as JsonSuite).suite === "string" &&
    Array.isArray((value as JsonSuite).tests)
  );
}

/** Normalize one suite's tests, validating each entry. */
function suiteCases(suite: JsonSuite, source: string): TestCaseResult[] {
  return suite.tests.map((t, i) => {
    if (typeof t?.name !== "string") {
      throw new Error(
        `Failed to parse "${source}": test #${i} in suite "${suite.suite}" is missing a "name"`,
      );
    }
    if (!VALID_STATUSES.has(t.status)) {
      throw new Error(
        `Failed to parse "${source}": test "${t.name}" has invalid status "${t.status}" (expected passed|failed|skipped)`,
      );
    }
    const result: TestCaseResult = {
      suite: suite.suite,
      name: t.name,
      status: t.status as TestStatus,
      durationSec: typeof t.duration === "number" ? t.duration : 0,
    };
    if (typeof t.message === "string") result.message = t.message;
    return result;
  });
}

/**
 * Parse a JSON results document into a normalized `TestFileResult`.
 *
 * @param text   Raw JSON text.
 * @param source Label for error messages and the result (e.g. file path).
 * @throws Error on invalid JSON or an unrecognized document shape.
 */
export function parseJsonResults(text: string, source: string): TestFileResult {
  let doc: unknown;
  try {
    doc = JSON.parse(text);
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to parse "${source}": not valid JSON (${detail})`);
  }

  let suites: JsonSuite[];
  if (isJsonSuite(doc)) {
    suites = [doc];
  } else if (
    typeof doc === "object" &&
    doc !== null &&
    Array.isArray((doc as { suites?: unknown }).suites) &&
    (doc as { suites: unknown[] }).suites.every(isJsonSuite)
  ) {
    suites = (doc as { suites: JsonSuite[] }).suites;
  } else {
    throw new Error(
      `Failed to parse "${source}": expected {"suite", "tests"} or {"suites": [...]}`,
    );
  }

  return { source, cases: suites.flatMap((s) => suiteCases(s, source)) };
}
