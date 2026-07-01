import { describe, it, expect } from "bun:test";
import { parseJsonResults } from "../src/json-parser";

describe("parseJsonResults", () => {
  it("parses passed, failed, and skipped test cases from JSON", () => {
    const json = JSON.stringify({
      suite: "JsonSuite",
      tests: [
        { name: "testOne", status: "passed", duration: 0.2 },
        { name: "testTwo", status: "failed", duration: 0.4, message: "boom" },
        { name: "testThree", status: "skipped", duration: 0 },
      ],
    });

    const result = parseJsonResults(json, "run2.json");

    expect(result.source).toBe("run2.json");
    expect(result.tests).toHaveLength(3);

    const one = result.tests.find((t) => t.name === "testOne");
    expect(one?.status).toBe("passed");
    expect(one?.suite).toBe("JsonSuite");
    expect(one?.duration).toBe(0.2);

    const two = result.tests.find((t) => t.name === "testTwo");
    expect(two?.status).toBe("failed");
    expect(two?.message).toBe("boom");
  });

  it("throws a meaningful error for invalid JSON", () => {
    expect(() => parseJsonResults("{not valid json", "bad.json")).toThrow(/parse|json/i);
  });

  it("throws a meaningful error when the tests field is missing", () => {
    expect(() => parseJsonResults(JSON.stringify({ suite: "X" }), "missing.json")).toThrow(/tests/i);
  });
});
