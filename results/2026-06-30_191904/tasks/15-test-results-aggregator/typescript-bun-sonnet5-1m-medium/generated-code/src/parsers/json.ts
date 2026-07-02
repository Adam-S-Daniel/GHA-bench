// Parses the aggregator's own simple JSON test result format:
//   { "suiteName"?: string, "tests": [{ name, suite, status, duration, message? }] }

import type { ParsedFile, TestCase, TestStatus } from "../types";

const VALID_STATUSES: TestStatus[] = ["passed", "failed", "skipped"];

export function parseJsonResults(raw: string, source: string): ParsedFile {
  let data: unknown;
  try {
    data = JSON.parse(raw);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to parse JSON from "${source}": ${reason}`);
  }

  if (typeof data !== "object" || data === null || !("tests" in data)) {
    throw new Error(`Failed to parse JSON from "${source}": missing "tests" array`);
  }

  const rawTests = (data as { tests: unknown }).tests;
  if (!Array.isArray(rawTests)) {
    throw new Error(`Failed to parse JSON from "${source}": missing "tests" array`);
  }

  const tests: TestCase[] = rawTests.map((entry, index) => {
    if (typeof entry !== "object" || entry === null) {
      throw new Error(`Failed to parse JSON from "${source}": test at index ${index} is not an object`);
    }
    const e = entry as Record<string, unknown>;

    if (typeof e.name !== "string" || e.name.length === 0) {
      throw new Error(`Failed to parse JSON from "${source}": test at index ${index} is missing a "name"`);
    }
    if (typeof e.status !== "string" || !VALID_STATUSES.includes(e.status as TestStatus)) {
      throw new Error(
        `Failed to parse JSON from "${source}": test "${e.name}" has invalid status "${String(e.status)}"`,
      );
    }

    const suite = typeof e.suite === "string" ? e.suite : "unknown";
    const duration = typeof e.duration === "number" ? e.duration : 0;
    const message = typeof e.message === "string" ? e.message : undefined;

    return {
      name: e.name,
      suite,
      status: e.status as TestStatus,
      duration,
      ...(message ? { message } : {}),
    };
  });

  return { source, format: "json", tests };
}
