import { describe, expect, test } from "bun:test";
import { parseJsonResults } from "../src/parsers/json";

describe("parseJsonResults", () => {
  test("parses a well-formed JSON test result file", async () => {
    const raw = await Bun.file("fixtures/json-simple.json").text();
    const result = parseJsonResults(raw, "json-simple.json");

    expect(result.source).toBe("json-simple.json");
    expect(result.format).toBe("json");
    expect(result.tests).toHaveLength(3);

    expect(result.tests[0]).toMatchObject({
      name: "server starts",
      suite: "Server",
      status: "passed",
      duration: 1.5,
    });

    expect(result.tests[1]).toMatchObject({
      name: "health check responds",
      suite: "Server",
      status: "failed",
      duration: 0.4,
      message: "connection refused",
    });

    expect(result.tests[2]).toMatchObject({
      name: "metrics endpoint",
      suite: "Server",
      status: "skipped",
      duration: 0,
    });
  });

  test("throws a meaningful error on invalid JSON", () => {
    expect(() => parseJsonResults("{ not valid json", "bad.json")).toThrow(/Failed to parse JSON/);
  });

  test("throws a meaningful error when 'tests' field is missing", () => {
    expect(() => parseJsonResults('{"suiteName": "x"}', "bad-shape.json")).toThrow(/missing "tests" array/);
  });

  test("throws a meaningful error when a test has an invalid status", () => {
    const raw = JSON.stringify({ tests: [{ name: "a", suite: "s", status: "bogus", duration: 0 }] });
    expect(() => parseJsonResults(raw, "bad-status.json")).toThrow(/invalid status "bogus"/);
  });
});
