import type { ParsedFile, TestCaseResult } from "./types";

interface RawJsonTestCase {
  name: string;
  status: "passed" | "failed" | "skipped";
  duration?: number;
  message?: string;
}

interface RawJsonReport {
  suite?: string;
  tests?: RawJsonTestCase[];
}

export function parseJsonResults(json: string, source: string): ParsedFile {
  let parsed: RawJsonReport;
  try {
    parsed = JSON.parse(json);
  } catch (err) {
    throw new Error(`Failed to parse JSON test results in "${source}": ${(err as Error).message}`);
  }

  if (!Array.isArray(parsed.tests)) {
    throw new Error(`Invalid JSON test results in "${source}": missing required "tests" array field`);
  }

  const suiteName = parsed.suite ?? "unknown";

  const tests: TestCaseResult[] = parsed.tests.map((t) => ({
    name: t.name,
    suite: suiteName,
    status: t.status,
    duration: t.duration ?? 0,
    message: t.message,
  }));

  return { source, tests };
}
