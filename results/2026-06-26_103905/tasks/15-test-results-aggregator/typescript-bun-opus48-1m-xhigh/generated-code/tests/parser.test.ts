/**
 * Parser tests.
 *
 * Written test-first (red/green TDD): each `describe` block adds behaviour
 * that the implementation in `src/parser.ts` must satisfy. We cover both the
 * JUnit XML and JSON formats plus the format-dispatch and error paths.
 */
import { describe, expect, test } from "bun:test";
import {
  parseJUnitXml,
  parseJsonResults,
  parseContent,
  parseFile,
} from "../src/parser.ts";

describe("parseJUnitXml", () => {
  test("parses passed, failed and skipped cases with durations", () => {
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="MathSuite" tests="3" failures="1" skipped="1" time="0.6">
    <testcase classname="MathSuite" name="test_add" time="0.10"/>
    <testcase classname="MathSuite" name="test_divide" time="0.30">
      <failure message="expected 2 but got 3">AssertionError</failure>
    </testcase>
    <testcase classname="MathSuite" name="test_pending" time="0.0">
      <skipped/>
    </testcase>
  </testsuite>
</testsuites>`;
    const run = parseJUnitXml(xml, "run-1.xml");
    expect(run.source).toBe("run-1.xml");
    expect(run.cases).toHaveLength(3);

    const add = run.cases[0]!;
    expect(add.name).toBe("test_add");
    expect(add.suite).toBe("MathSuite");
    expect(add.status).toBe("passed");
    expect(add.duration).toBeCloseTo(0.1, 5);

    const divide = run.cases[1]!;
    expect(divide.status).toBe("failed");
    expect(divide.message).toBe("expected 2 but got 3");

    expect(run.cases[2]!.status).toBe("skipped");
  });

  test("treats <error> elements as failures", () => {
    const xml = `<testsuite name="S" tests="1">
      <testcase name="boom" time="1.0"><error message="kaboom"/></testcase>
    </testsuite>`;
    const run = parseJUnitXml(xml, "err.xml");
    expect(run.cases[0]!.status).toBe("failed");
    expect(run.cases[0]!.message).toBe("kaboom");
  });

  test("supports a bare <testsuite> root (no <testsuites> wrapper)", () => {
    const xml = `<testsuite name="S" tests="1">
      <testcase classname="S" name="only" time="0.5"/>
    </testsuite>`;
    const run = parseJUnitXml(xml, "bare.xml");
    expect(run.cases).toHaveLength(1);
    expect(run.cases[0]!.status).toBe("passed");
  });

  test("defaults missing time attribute to 0", () => {
    const xml = `<testsuite><testcase name="notime"/></testsuite>`;
    const run = parseJUnitXml(xml, "n.xml");
    expect(run.cases[0]!.duration).toBe(0);
  });

  test("throws a meaningful error when no testcases are present", () => {
    expect(() => parseJUnitXml("<testsuites></testsuites>", "empty.xml")).toThrow(
      /no <testcase> elements/i,
    );
  });
});

describe("parseJsonResults", () => {
  test("parses the canonical object form with a tests array", () => {
    const json = JSON.stringify({
      name: "run-3",
      tests: [
        { name: "test_add", suite: "MathSuite", status: "passed", duration: 0.1 },
        {
          name: "test_divide",
          suite: "MathSuite",
          status: "failed",
          duration: 0.3,
          message: "boom",
        },
        { name: "test_split", suite: "StringSuite", status: "skipped" },
      ],
    });
    const run = parseJsonResults(json, "run-3.json");
    expect(run.source).toBe("run-3");
    expect(run.cases).toHaveLength(3);
    expect(run.cases[1]!.status).toBe("failed");
    expect(run.cases[1]!.message).toBe("boom");
    // duration omitted -> defaults to 0
    expect(run.cases[2]!.duration).toBe(0);
  });

  test("accepts a top-level array of test cases", () => {
    const json = JSON.stringify([
      { name: "a", status: "pass", duration: 1 },
      { name: "b", status: "fail", duration: 2 },
    ]);
    const run = parseJsonResults(json, "arr.json");
    expect(run.cases).toHaveLength(2);
    expect(run.cases[0]!.status).toBe("passed");
    expect(run.cases[1]!.status).toBe("failed");
  });

  test("normalises status synonyms (pass/fail/skip/error)", () => {
    const json = JSON.stringify({
      tests: [
        { name: "a", status: "PASS" },
        { name: "b", status: "Failure" },
        { name: "c", status: "skip" },
        { name: "d", status: "error" },
        { name: "e", status: "ok" },
      ],
    });
    const run = parseJsonResults(json, "syn.json");
    expect(run.cases.map((c) => c.status)).toEqual([
      "passed",
      "failed",
      "skipped",
      "failed",
      "passed",
    ]);
  });

  test("throws on invalid JSON with a meaningful message", () => {
    expect(() => parseJsonResults("{not json", "bad.json")).toThrow(
      /failed to parse JSON/i,
    );
  });

  test("throws when an unknown status value is encountered", () => {
    const json = JSON.stringify({ tests: [{ name: "x", status: "weird" }] });
    expect(() => parseJsonResults(json, "u.json")).toThrow(/unknown.*status/i);
  });
});

describe("parseContent (format dispatch by extension)", () => {
  test("routes .xml to the JUnit parser", () => {
    const run = parseContent(
      `<testsuite><testcase name="t" time="0.2"/></testsuite>`,
      "x.xml",
    );
    expect(run.cases[0]!.name).toBe("t");
  });

  test("routes .json to the JSON parser", () => {
    const run = parseContent(
      JSON.stringify({ tests: [{ name: "j", status: "passed" }] }),
      "y.json",
    );
    expect(run.cases[0]!.name).toBe("j");
  });

  test("throws for unsupported extensions", () => {
    expect(() => parseContent("data", "z.txt")).toThrow(/unsupported.*format/i);
  });
});

describe("parseFile (reads from disk)", () => {
  test("parses an on-disk JUnit fixture", async () => {
    const run = await parseFile("fixtures/sample/run-1.xml");
    expect(run.cases.length).toBeGreaterThan(0);
  });

  test("throws a clear error when the file does not exist", async () => {
    await expect(parseFile("fixtures/does-not-exist.xml")).rejects.toThrow(
      /could not read/i,
    );
  });
});
