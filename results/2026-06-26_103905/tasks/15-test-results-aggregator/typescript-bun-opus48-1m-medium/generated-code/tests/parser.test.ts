import { describe, expect, test } from "bun:test";
import { parseJUnitXml, parseJsonResults, parseContent } from "../src/parser.ts";

// --- JUnit XML parsing -----------------------------------------------------

describe("parseJUnitXml", () => {
  test("parses passed, failed, and skipped testcases", () => {
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="MathTest" tests="3" failures="1" skipped="1" time="1.5">
    <testcase name="adds" classname="MathTest" time="0.5"/>
    <testcase name="divides" classname="MathTest" time="0.6">
      <failure message="expected 2 but got 3">stack trace here</failure>
    </testcase>
    <testcase name="subtracts" classname="MathTest" time="0.4">
      <skipped/>
    </testcase>
  </testsuite>
</testsuites>`;

    const results = parseJUnitXml(xml);
    expect(results).toHaveLength(3);

    expect(results[0]).toEqual({
      name: "adds",
      suite: "MathTest",
      status: "passed",
      duration: 0.5,
    });
    expect(results[1]).toMatchObject({
      name: "divides",
      suite: "MathTest",
      status: "failed",
      duration: 0.6,
      message: "expected 2 but got 3",
    });
    expect(results[2]).toMatchObject({
      name: "subtracts",
      status: "skipped",
      duration: 0.4,
    });
  });

  test("handles an <error> element as a failure", () => {
    const xml = `<testsuite name="S"><testcase name="boom" classname="S" time="0">
      <error message="kaboom"/></testcase></testsuite>`;
    const results = parseJUnitXml(xml);
    expect(results[0]).toMatchObject({ status: "failed", message: "kaboom" });
  });

  test("throws a meaningful error on malformed XML", () => {
    expect(() => parseJUnitXml("not xml at all {}"))
      .toThrow(/no <testcase> elements/i);
  });
});

// --- JSON parsing ----------------------------------------------------------

describe("parseJsonResults", () => {
  test("parses our JSON result schema", () => {
    const json = JSON.stringify({
      tests: [
        { name: "adds", suite: "MathTest", status: "passed", duration: 0.5 },
        { name: "divides", suite: "MathTest", status: "failed", duration: 0.6, message: "nope" },
      ],
    });
    const results = parseJsonResults(json);
    expect(results).toHaveLength(2);
    expect(results[1]).toMatchObject({ status: "failed", message: "nope" });
  });

  test("defaults missing duration to 0 and missing suite to empty string", () => {
    const json = JSON.stringify({ tests: [{ name: "x", status: "passed" }] });
    const results = parseJsonResults(json);
    expect(results[0]).toEqual({ name: "x", suite: "", status: "passed", duration: 0 });
  });

  test("throws on invalid status values", () => {
    const json = JSON.stringify({ tests: [{ name: "x", status: "exploded" }] });
    expect(() => parseJsonResults(json)).toThrow(/invalid status/i);
  });

  test("throws a meaningful error on non-JSON input", () => {
    expect(() => parseJsonResults("{ broken")).toThrow(/failed to parse JSON/i);
  });
});

// --- format dispatch -------------------------------------------------------

describe("parseContent", () => {
  test("dispatches to XML parser for .xml files", () => {
    const xml = `<testsuite name="S"><testcase name="t" classname="S" time="1"/></testsuite>`;
    expect(parseContent("results.xml", xml)).toHaveLength(1);
  });

  test("dispatches to JSON parser for .json files", () => {
    const json = JSON.stringify({ tests: [{ name: "t", status: "passed" }] });
    expect(parseContent("results.json", json)).toHaveLength(1);
  });

  test("throws for unsupported extensions", () => {
    expect(() => parseContent("results.txt", "")).toThrow(/unsupported/i);
  });
});
