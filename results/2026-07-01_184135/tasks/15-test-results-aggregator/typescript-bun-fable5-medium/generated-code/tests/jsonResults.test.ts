/**
 * TDD cycle 2 (RED): JSON results parser.
 *
 * Supported JSON schema (a common lightweight CI reporter shape):
 *   { "suite": "api", "tests": [ { "name", "status", "duration", "message?" } ] }
 * or multiple suites at once:
 *   { "suites": [ { "suite", "tests": [...] } ] }
 * `duration` is in seconds. Invalid JSON or an unrecognized shape must raise
 * a descriptive error naming the source file.
 */
import { describe, expect, test } from "bun:test";
import { parseJsonResults } from "../src/jsonResults";

describe("parseJsonResults", () => {
  test("parses a single-suite document", () => {
    const json = JSON.stringify({
      suite: "api",
      tests: [
        { name: "GET /users", status: "passed", duration: 0.12 },
        { name: "POST /users", status: "failed", duration: 0.4, message: "500" },
        { name: "DELETE /users", status: "skipped" },
      ],
    });
    const result = parseJsonResults(json, "api.json");
    expect(result.source).toBe("api.json");
    expect(result.cases).toEqual([
      { suite: "api", name: "GET /users", status: "passed", durationSec: 0.12 },
      { suite: "api", name: "POST /users", status: "failed", durationSec: 0.4, message: "500" },
      { suite: "api", name: "DELETE /users", status: "skipped", durationSec: 0 },
    ]);
  });

  test("parses a multi-suite document", () => {
    const json = JSON.stringify({
      suites: [
        { suite: "a", tests: [{ name: "t1", status: "passed", duration: 1 }] },
        { suite: "b", tests: [{ name: "t2", status: "failed", duration: 2 }] },
      ],
    });
    const result = parseJsonResults(json, "multi.json");
    expect(result.cases).toHaveLength(2);
    expect(result.cases[1]!.suite).toBe("b");
  });

  test("rejects invalid JSON with the source name in the message", () => {
    expect(() => parseJsonResults("{not json", "bad.json")).toThrow(
      /bad\.json.*not valid JSON/i,
    );
  });

  test("rejects an unrecognized shape", () => {
    expect(() => parseJsonResults('{"foo": 1}', "odd.json")).toThrow(
      /odd\.json.*expected .*suite/i,
    );
  });

  test("rejects an invalid test status", () => {
    const json = JSON.stringify({
      suite: "s",
      tests: [{ name: "t", status: "exploded" }],
    });
    expect(() => parseJsonResults(json, "status.json")).toThrow(
      /invalid status "exploded"/i,
    );
  });
});
