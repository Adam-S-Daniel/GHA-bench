import { describe, expect, test } from "bun:test";
import { parseJUnitXml } from "../src/parsers/junit";

describe("parseJUnitXml", () => {
  test("parses passed, failed, and skipped test cases from nested testsuites", async () => {
    const xml = await Bun.file("fixtures/junit-run-ubuntu-node18.xml").text();
    const result = parseJUnitXml(xml, "junit-run-ubuntu-node18.xml");

    expect(result.source).toBe("junit-run-ubuntu-node18.xml");
    expect(result.format).toBe("junit");
    expect(result.tests).toHaveLength(4);

    const byName = Object.fromEntries(result.tests.map((t) => [t.name, t]));

    expect(byName["adds two numbers"]).toMatchObject({
      suite: "MathUtils",
      status: "passed",
      duration: 0.3,
    });

    expect(byName["divides by zero throws"]).toMatchObject({
      suite: "MathUtils",
      status: "failed",
      duration: 0.25,
    });
    expect(byName["divides by zero throws"]?.message).toContain("Expected error to be thrown");

    expect(byName["reverses a string"]).toMatchObject({
      suite: "StringUtils",
      status: "passed",
      duration: 0.1,
    });

    expect(byName["handles unicode"]).toMatchObject({
      suite: "StringUtils",
      status: "skipped",
      duration: 0.2,
    });
  });

  test("throws a meaningful error on malformed XML", () => {
    expect(() => parseJUnitXml("<testsuites><testsuite", "bad.xml")).toThrow(/Failed to parse JUnit XML/);
  });
});
