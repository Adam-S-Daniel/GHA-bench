// Parsers that normalize external test-result formats into our internal
// `TestResult` shape.
//
// Two input formats are supported:
//   * JUnit XML   — the de-facto interchange format emitted by most runners.
//   * JSON        — a small, explicit schema (see `parseJsonResults`).
//
// We deliberately avoid a heavyweight XML dependency. JUnit XML is regular
// enough that a focused, well-commented regex tokenizer is both simpler and
// dependency-free (which keeps the CI container light). The tokenizer only
// understands the subset of JUnit that matters here: <testcase> elements and
// their <failure>/<error>/<skipped> children.

import type { TestResult, TestStatus } from "./types.ts";

const VALID_STATUSES: ReadonlySet<string> = new Set([
  "passed",
  "failed",
  "skipped",
]);

/** Decode the handful of XML entities that appear in JUnit attribute values. */
function decodeEntities(text: string): string {
  return text
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

/** Read an attribute value from a raw element's attribute string. */
function attr(attrs: string, name: string): string | undefined {
  const m = attrs.match(new RegExp(`${name}\\s*=\\s*"([^"]*)"`));
  return m ? decodeEntities(m[1]) : undefined;
}

/**
 * Parse JUnit XML into a flat list of test executions.
 *
 * Matches each <testcase ...> element, whether self-closing (`<testcase .../>`)
 * or with a body (`<testcase ...>...</testcase>`). A body containing a
 * <failure> or <error> marks the case failed; a <skipped> marks it skipped;
 * otherwise it passed.
 */
export function parseJUnitXml(xml: string): TestResult[] {
  const results: TestResult[] = [];

  // Capture: (1) attribute string, (2) optional body. Non-greedy body so each
  // testcase is matched independently.
  const caseRe =
    /<testcase\b([^>]*?)(?:\/>|>([\s\S]*?)<\/testcase>)/g;

  let match: RegExpExecArray | null;
  while ((match = caseRe.exec(xml)) !== null) {
    const attrs = match[1] ?? "";
    const body = match[2] ?? "";

    const name = attr(attrs, "name") ?? "";
    // JUnit uses `classname`; fall back to a `suite`/`testsuite` attr if present.
    const suite =
      attr(attrs, "classname") ?? attr(attrs, "suite") ?? "";
    const duration = parseFloat(attr(attrs, "time") ?? "0") || 0;

    let status: TestStatus = "passed";
    let message: string | undefined;

    const failureMatch = body.match(/<(failure|error)\b([^>]*)(?:\/>|>)/);
    const skippedMatch = body.match(/<skipped\b/);

    if (failureMatch) {
      status = "failed";
      message = attr(failureMatch[2] ?? "", "message");
    } else if (skippedMatch) {
      status = "skipped";
    }

    const result: TestResult = { name, suite, status, duration };
    if (message !== undefined) result.message = message;
    results.push(result);
  }

  if (results.length === 0) {
    throw new Error(
      "Invalid JUnit XML: no <testcase> elements were found. " +
        "Expected a <testsuites>/<testsuite> document containing <testcase> entries.",
    );
  }

  return results;
}

/** Shape of the JSON result schema we accept. */
interface JsonTest {
  name: string;
  suite?: string;
  status?: string;
  duration?: number;
  message?: string;
}

/**
 * Parse our JSON result schema:
 *   { "tests": [ { name, suite?, status, duration?, message? }, ... ] }
 *
 * Missing `suite` defaults to "", missing `duration` to 0. An unrecognized
 * `status` is a hard error — silently dropping it would corrupt the totals.
 */
export function parseJsonResults(json: string): TestResult[] {
  let data: unknown;
  try {
    data = JSON.parse(json);
  } catch (err) {
    throw new Error(
      `Failed to parse JSON results: ${(err as Error).message}`,
    );
  }

  if (
    typeof data !== "object" ||
    data === null ||
    !Array.isArray((data as { tests?: unknown }).tests)
  ) {
    throw new Error(
      'Invalid JSON results: expected an object with a "tests" array.',
    );
  }

  const tests = (data as { tests: JsonTest[] }).tests;
  return tests.map((t, i): TestResult => {
    if (typeof t.name !== "string" || t.name.length === 0) {
      throw new Error(`Invalid JSON results: test #${i} is missing a "name".`);
    }
    const status = t.status ?? "passed";
    if (!VALID_STATUSES.has(status)) {
      throw new Error(
        `Invalid status "${status}" for test "${t.name}". ` +
          `Expected one of: passed, failed, skipped.`,
      );
    }
    const result: TestResult = {
      name: t.name,
      suite: t.suite ?? "",
      status: status as TestStatus,
      duration: typeof t.duration === "number" ? t.duration : 0,
    };
    if (typeof t.message === "string") result.message = t.message;
    return result;
  });
}

/**
 * Dispatch to the correct parser based on file extension. The single entry
 * point used by the CLI and aggregator.
 */
export function parseContent(filename: string, content: string): TestResult[] {
  const lower = filename.toLowerCase();
  if (lower.endsWith(".xml")) return parseJUnitXml(content);
  if (lower.endsWith(".json")) return parseJsonResults(content);
  throw new Error(
    `Unsupported file format for "${filename}". ` +
      `Expected a .xml (JUnit) or .json results file.`,
  );
}
