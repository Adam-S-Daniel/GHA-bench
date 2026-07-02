import type { TestCase, TestSuiteResult, TestStatus } from "../types";

const VALID_STATUSES: readonly TestStatus[] = ["passed", "failed", "skipped"];

function isValidStatus(value: unknown): value is TestStatus {
  return VALID_STATUSES.includes(value as TestStatus);
}

/**
 * Parses the JSON test result format:
 * { "suiteName": string, "tests": [{ name, classname?, status, duration?, message? }] }
 */
export function parseJsonResults(raw: string, source: string): TestSuiteResult {
  let data: unknown;
  try {
    data = JSON.parse(raw);
  } catch (err) {
    throw new Error(
      `Failed to parse JSON test results from "${source}": invalid JSON (${(err as Error).message})`,
    );
  }

  if (typeof data !== "object" || data === null) {
    throw new Error(
      `Failed to parse JSON test results from "${source}": expected a JSON object`,
    );
  }

  const obj = data as Record<string, unknown>;

  if (typeof obj.suiteName !== "string") {
    throw new Error(
      `Failed to parse JSON test results from "${source}": missing required "suiteName" string field`,
    );
  }

  if (!Array.isArray(obj.tests)) {
    throw new Error(
      `Failed to parse JSON test results from "${source}": missing required "tests" array field`,
    );
  }

  const tests: TestCase[] = obj.tests.map((rawTest, index) => {
    if (typeof rawTest !== "object" || rawTest === null) {
      throw new Error(
        `Failed to parse JSON test results from "${source}": tests[${index}] must be an object`,
      );
    }
    const t = rawTest as Record<string, unknown>;

    if (typeof t.name !== "string") {
      throw new Error(
        `Failed to parse JSON test results from "${source}": tests[${index}] missing required "name" string field`,
      );
    }

    if (!isValidStatus(t.status)) {
      throw new Error(
        `Failed to parse JSON test results from "${source}": tests[${index}] has invalid "status" (must be one of ${VALID_STATUSES.join(", ")})`,
      );
    }

    const testCase: TestCase = {
      name: t.name,
      classname: typeof t.classname === "string" ? t.classname : "",
      status: t.status,
      duration: typeof t.duration === "number" ? t.duration : 0,
    };
    if (typeof t.message === "string") {
      testCase.message = t.message;
    }
    return testCase;
  });

  return { suiteName: obj.suiteName, source, tests };
}
