/**
 * TDD Cycle 2 — JSON results parser.
 *
 * The JSON format is our own simple schema (documented in src/parsers/json.ts):
 *   { "tests": [ { "suite", "name", "status", "duration", "message"? } ] }
 *
 * RED: failed with module-resolution error before src/parsers/json.ts existed.
 */
import { describe, expect, test } from "bun:test";
import { parseJsonResults } from "../src/parsers/json";

const SAMPLE = JSON.stringify({
  tests: [
    { suite: "api", name: "test_create", status: "passed", duration: 0.2 },
    { suite: "api", name: "test_delete", status: "failed", duration: 0.7, message: "500 from server" },
    { suite: "api", name: "test_patch", status: "skipped", duration: 0 },
  ],
});

describe("parseJsonResults", () => {
  test("parses all test entries with statuses and durations", () => {
    const run = parseJsonResults(SAMPLE, "shard3.json");
    expect(run.source).toBe("shard3.json");
    expect(run.cases).toHaveLength(3);
    expect(run.cases[0]).toEqual({
      suite: "api",
      name: "test_create",
      status: "passed",
      durationSeconds: 0.2,
    });
    expect(run.cases[1]?.status).toBe("failed");
    expect(run.cases[1]?.message).toBe("500 from server");
    expect(run.cases[2]?.status).toBe("skipped");
  });

  test("defaults a missing duration to 0", () => {
    const run = parseJsonResults(
      JSON.stringify({ tests: [{ suite: "s", name: "t", status: "passed" }] }),
      "x.json",
    );
    expect(run.cases[0]?.durationSeconds).toBe(0);
  });

  test("throws a meaningful error for invalid JSON syntax", () => {
    expect(() => parseJsonResults("{not json", "bad.json")).toThrow(/bad\.json.*not valid JSON/i);
  });

  test("throws a meaningful error when the tests array is missing", () => {
    expect(() => parseJsonResults('{"foo": 1}', "bad.json")).toThrow(
      /bad\.json.*"tests" array/i,
    );
  });

  test("throws a meaningful error for an unknown status value", () => {
    const doc = JSON.stringify({ tests: [{ suite: "s", name: "t", status: "exploded" }] });
    expect(() => parseJsonResults(doc, "bad.json")).toThrow(/bad\.json.*status "exploded"/i);
  });

  test("throws a meaningful error when a test entry has no name", () => {
    const doc = JSON.stringify({ tests: [{ suite: "s", status: "passed" }] });
    expect(() => parseJsonResults(doc, "bad.json")).toThrow(/bad\.json.*missing.*name/i);
  });
});
