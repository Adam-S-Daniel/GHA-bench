import { describe, expect, test } from "bun:test";
import { parseJsonResults } from "../src/parsers/json";

describe("parseJsonResults", () => {
  test("parses passed and failed test cases from JSON", async () => {
    const raw = await Bun.file("fixtures/results-integration-node18.json").text();
    const suite = parseJsonResults(raw, "fixtures/results-integration-node18.json");

    expect(suite.suiteName).toBe("IntegrationTests");
    expect(suite.source).toBe("fixtures/results-integration-node18.json");
    expect(suite.tests).toHaveLength(3);

    expect(suite.tests[0]).toEqual({
      name: "testLogin",
      classname: "AuthTests",
      status: "passed",
      duration: 0.512,
    });

    const tokenRefresh = suite.tests.find((t) => t.name === "testTokenRefresh");
    expect(tokenRefresh?.status).toBe("failed");
    expect(tokenRefresh?.message).toBe("timeout waiting for refresh token");
  });

  test("defaults classname to empty string and duration to 0 when omitted", () => {
    const raw = JSON.stringify({
      suiteName: "Minimal",
      tests: [{ name: "bareTest", status: "passed" }],
    });
    const suite = parseJsonResults(raw, "minimal.json");
    expect(suite.tests[0]).toEqual({
      name: "bareTest",
      classname: "",
      status: "passed",
      duration: 0,
    });
  });

  test("throws a descriptive error for malformed JSON", async () => {
    const raw = await Bun.file("fixtures/invalid/malformed.json").text();
    expect(() => parseJsonResults(raw, "fixtures/invalid/malformed.json")).toThrow(
      /malformed.json/,
    );
  });

  test("throws a descriptive error when required fields are missing", () => {
    expect(() => parseJsonResults(JSON.stringify({}), "bad.json")).toThrow(
      /suiteName/,
    );
    expect(() =>
      parseJsonResults(JSON.stringify({ suiteName: "X" }), "bad.json"),
    ).toThrow(/tests/);
  });

  test("throws a descriptive error for an invalid status value", () => {
    const raw = JSON.stringify({
      suiteName: "Bad",
      tests: [{ name: "t", status: "unknown-status" }],
    });
    expect(() => parseJsonResults(raw, "bad.json")).toThrow(/status/);
  });
});
