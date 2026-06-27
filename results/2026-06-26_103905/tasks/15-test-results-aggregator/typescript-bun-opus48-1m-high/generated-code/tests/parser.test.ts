import { describe, expect, it } from "bun:test";
import { parseJUnitXml, parseJson, parseContent } from "../src/parser.ts";

describe("parseJUnitXml", () => {
  it("parses a simple JUnit XML with passed, failed, and skipped cases", () => {
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="math.suite" tests="3" failures="1" skipped="1" time="0.5">
    <testcase classname="math.suite" name="adds" time="0.1"/>
    <testcase classname="math.suite" name="divides" time="0.2">
      <failure message="boom">stack</failure>
    </testcase>
    <testcase classname="math.suite" name="ignored" time="0">
      <skipped/>
    </testcase>
  </testsuite>
</testsuites>`;

    const run = parseJUnitXml(xml, "junit.xml");
    expect(run.name).toBe("junit.xml");
    expect(run.cases).toHaveLength(3);

    const adds = run.cases.find((c) => c.name === "adds")!;
    expect(adds.status).toBe("passed");
    expect(adds.suite).toBe("math.suite");
    expect(adds.duration).toBeCloseTo(0.1);

    expect(run.cases.find((c) => c.name === "divides")!.status).toBe("failed");
    expect(run.cases.find((c) => c.name === "ignored")!.status).toBe("skipped");
  });

  it("treats <error> cases as failed", () => {
    const xml = `<testsuite name="s" tests="1">
      <testcase name="errs" time="0.3"><error message="x"/></testcase>
    </testsuite>`;
    const run = parseJUnitXml(xml, "e.xml");
    expect(run.cases[0]!.status).toBe("failed");
  });

  it("throws a meaningful error on malformed XML", () => {
    expect(() => parseJUnitXml("not xml at all <<<", "bad.xml")).toThrow(
      /Failed to parse JUnit XML/,
    );
  });
});

describe("parseJson", () => {
  it("parses the canonical JSON test report shape", () => {
    const json = JSON.stringify({
      tests: [
        { name: "a", suite: "grp", status: "passed", duration: 0.4 },
        { name: "b", suite: "grp", status: "failed", duration: 0.6 },
        { name: "c", status: "skipped" },
      ],
    });
    const run = parseJson(json, "report.json");
    expect(run.cases).toHaveLength(3);
    expect(run.cases[0]!.status).toBe("passed");
    expect(run.cases[2]!.suite).toBe("");
    expect(run.cases[2]!.duration).toBe(0);
  });

  it("accepts a bare array of tests", () => {
    const json = JSON.stringify([{ name: "x", status: "passed" }]);
    const run = parseJson(json, "arr.json");
    expect(run.cases).toHaveLength(1);
  });

  it("normalizes pass/fail/skip aliases", () => {
    const json = JSON.stringify({
      tests: [
        { name: "a", status: "pass" },
        { name: "b", status: "FAIL" },
        { name: "c", status: "skip" },
      ],
    });
    const run = parseJson(json, "aliases.json");
    expect(run.cases.map((c) => c.status)).toEqual([
      "passed",
      "failed",
      "skipped",
    ]);
  });

  it("throws a meaningful error on invalid JSON", () => {
    expect(() => parseJson("{ not json", "bad.json")).toThrow(
      /Failed to parse JSON/,
    );
  });

  it("throws on an unknown status value", () => {
    const json = JSON.stringify({ tests: [{ name: "a", status: "weird" }] });
    expect(() => parseJson(json, "x.json")).toThrow(/Unknown test status/);
  });
});

describe("parseContent (format dispatch by extension)", () => {
  it("dispatches .xml to the JUnit parser", () => {
    const run = parseContent(
      `<testsuite name="s"><testcase name="t" time="0.1"/></testsuite>`,
      "a.xml",
    );
    expect(run.cases[0]!.name).toBe("t");
  });

  it("dispatches .json to the JSON parser", () => {
    const run = parseContent(`[{"name":"t","status":"passed"}]`, "a.json");
    expect(run.cases[0]!.name).toBe("t");
  });

  it("throws on an unsupported extension", () => {
    expect(() => parseContent("x", "a.txt")).toThrow(/Unsupported file format/);
  });
});
