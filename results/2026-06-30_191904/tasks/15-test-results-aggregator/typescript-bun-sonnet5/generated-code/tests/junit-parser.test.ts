import { describe, expect, test } from "bun:test";
import { parseJUnitXml } from "../src/parsers/junit";

describe("parseJUnitXml", () => {
  test("parses passed, failed, and skipped test cases with durations", async () => {
    const xml = await Bun.file("fixtures/junit-ubuntu-node18.xml").text();
    const suite = parseJUnitXml(xml, "fixtures/junit-ubuntu-node18.xml");

    expect(suite.suiteName).toBe("UnitTests");
    expect(suite.source).toBe("fixtures/junit-ubuntu-node18.xml");
    expect(suite.tests).toHaveLength(5);

    const add = suite.tests.find((t) => t.name === "testAdd");
    expect(add).toEqual({
      name: "testAdd",
      classname: "math.Calculator",
      status: "passed",
      duration: 0.012,
    });

    const divideByZero = suite.tests.find((t) => t.name === "testDivideByZero");
    expect(divideByZero?.status).toBe("failed");
    expect(divideByZero?.duration).toBeCloseTo(0.045);
    expect(divideByZero?.message).toBe("Division by zero not handled");

    const legacyMultiply = suite.tests.find((t) => t.name === "testLegacyMultiply");
    expect(legacyMultiply?.status).toBe("skipped");
  });

  test("throws a descriptive error for malformed XML", async () => {
    const xml = await Bun.file("fixtures/invalid/malformed.xml").text();
    expect(() => parseJUnitXml(xml, "fixtures/invalid/malformed.xml")).toThrow(
      /malformed.xml/,
    );
  });

  test("throws a descriptive error when no testsuite element is present", () => {
    expect(() => parseJUnitXml("<notasuite></notasuite>", "bad.xml")).toThrow(
      /testsuite/i,
    );
  });
});
