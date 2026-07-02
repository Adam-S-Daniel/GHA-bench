import { describe, it, expect } from "bun:test";
import { parseJUnitXml } from "../src/junit-parser";

describe("parseJUnitXml", () => {
  it("parses passed, failed, and skipped test cases from JUnit XML", () => {
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="ExampleSuite" tests="3" failures="1" skipped="1" time="1.234">
  <testcase name="testAdd" classname="ExampleSuite" time="0.5"/>
  <testcase name="testSubtract" classname="ExampleSuite" time="0.6">
    <failure message="expected 2 got 3">AssertionError</failure>
  </testcase>
  <testcase name="testDivide" classname="ExampleSuite" time="0.1">
    <skipped/>
  </testcase>
</testsuite>`;

    const result = parseJUnitXml(xml, "run1.xml");

    expect(result.source).toBe("run1.xml");
    expect(result.tests).toHaveLength(3);

    const add = result.tests.find((t) => t.name === "testAdd");
    expect(add?.status).toBe("passed");
    expect(add?.duration).toBe(0.5);
    expect(add?.suite).toBe("ExampleSuite");

    const subtract = result.tests.find((t) => t.name === "testSubtract");
    expect(subtract?.status).toBe("failed");
    expect(subtract?.message).toContain("expected 2 got 3");

    const divide = result.tests.find((t) => t.name === "testDivide");
    expect(divide?.status).toBe("skipped");
  });

  it("throws a meaningful error for malformed XML", () => {
    expect(() => parseJUnitXml("<not-valid", "bad.xml")).toThrow(/malformed|parse/i);
  });
});
