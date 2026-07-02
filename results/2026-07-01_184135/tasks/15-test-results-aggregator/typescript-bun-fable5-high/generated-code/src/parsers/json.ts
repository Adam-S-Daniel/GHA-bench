/**
 * JSON results parser.
 *
 * Expected schema (a deliberately simple, tool-agnostic format):
 *
 *   {
 *     "tests": [
 *       {
 *         "suite":   string   (optional, defaults to "(no suite)"),
 *         "name":    string   (required),
 *         "status":  "passed" | "failed" | "skipped"  (required),
 *         "duration": number  (seconds, optional, defaults to 0),
 *         "message": string   (optional failure message)
 *       }
 *     ]
 *   }
 *
 * Every validation failure names the source file and the offending value so a
 * CI log points straight at the broken report.
 */
import type { TestCaseResult, TestRun, TestStatus } from "../types";

const VALID_STATUSES: ReadonlySet<string> = new Set(["passed", "failed", "skipped"]);

export function parseJsonResults(content: string, source: string): TestRun {
  let doc: unknown;
  try {
    doc = JSON.parse(content);
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(`${source}: content is not valid JSON (${detail})`);
  }

  if (typeof doc !== "object" || doc === null || !Array.isArray((doc as { tests?: unknown }).tests)) {
    throw new Error(`${source}: expected a top-level "tests" array`);
  }

  const cases: TestCaseResult[] = (doc as { tests: unknown[] }).tests.map((entry, i) => {
    if (typeof entry !== "object" || entry === null) {
      throw new Error(`${source}: tests[${i}] is not an object`);
    }
    const t = entry as Record<string, unknown>;

    if (typeof t.name !== "string" || t.name === "") {
      throw new Error(`${source}: tests[${i}] is missing a "name" string`);
    }
    if (typeof t.status !== "string" || !VALID_STATUSES.has(t.status)) {
      throw new Error(
        `${source}: tests[${i}] ("${t.name}") has unknown status "${String(t.status)}" — expected passed|failed|skipped`,
      );
    }

    const duration = t.duration === undefined ? 0 : Number(t.duration);
    if (Number.isNaN(duration)) {
      throw new Error(`${source}: tests[${i}] ("${t.name}") has a non-numeric duration`);
    }

    return {
      suite: typeof t.suite === "string" && t.suite !== "" ? t.suite : "(no suite)",
      name: t.name,
      status: t.status as TestStatus,
      durationSeconds: duration,
      ...(typeof t.message === "string" ? { message: t.message } : {}),
    };
  });

  return { source, cases };
}
