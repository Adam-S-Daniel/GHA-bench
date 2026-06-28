/**
 * Tests for the format parsers. We start here (red/green TDD) because parsing
 * is the foundation everything else builds on. The JSON parser comes first as
 * it is the simpler of the two formats.
 */
import { describe, expect, test } from "bun:test";
import { parseJsonResults, parseJUnitXml, parseResultFile } from "../src/parsers";

describe("parseJsonResults", () => {
  test("parses a basic JSON run into normalised cases", () => {
    const json = JSON.stringify({
      name: "unit",
      tests: [
        { name: "adds", suite: "Math", status: "passed", duration: 0.01 },
        { name: "divides", suite: "Math", status: "failed", duration: 0.02, message: "boom" },
        { name: "todo", suite: "Math", status: "skipped" },
      ],
    });

    const run = parseJsonResults(json, "unit.json");

    expect(run.source).toBe("unit.json");
    expect(run.name).toBe("unit");
    expect(run.cases).toHaveLength(3);
    expect(run.cases[0]).toEqual({
      name: "adds",
      suite: "Math",
      status: "passed",
      durationSeconds: 0.01,
    });
    expect(run.cases[1]).toEqual({
      name: "divides",
      suite: "Math",
      status: "failed",
      durationSeconds: 0.02,
      message: "boom",
    });
    // A skipped test with no duration defaults to 0 seconds.
    expect(run.cases[2]).toEqual({
      name: "todo",
      suite: "Math",
      status: "skipped",
      durationSeconds: 0,
    });
  });

  test("accepts a bare top-level array and status aliases", () => {
    const json = JSON.stringify([
      { name: "a", status: "pass", time: 1 },
      { name: "b", status: "error", duration: 2 },
      { name: "c", status: "pending" },
    ]);
    const run = parseJsonResults(json, "arr.json");
    expect(run.name).toBe("");
    expect(run.cases.map((c) => c.status)).toEqual(["passed", "failed", "skipped"]);
    expect(run.cases[0]?.durationSeconds).toBe(1);
    expect(run.cases.map((c) => c.suite)).toEqual(["", "", ""]);
  });

  test("throws a source-named error on malformed JSON", () => {
    expect(() => parseJsonResults("{not json", "bad.json")).toThrow(/bad\.json/);
  });
});

describe("parseJUnitXml", () => {
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<!-- a comment that must be ignored -->
<testsuites name="all" tests="5" failures="1" errors="1" skipped="1">
  <testsuite name="MathSuite" tests="4" time="0.5">
    <testcase name="adds" classname="Math" time="0.1"/>
    <testcase name="subtracts" classname="Math" time="0.2"></testcase>
    <testcase name="divides" classname="Math" time="0.05">
      <failure message="expected 2 &amp; got 3">stack &lt;trace&gt;</failure>
    </testcase>
    <testcase name="explodes" classname="Math" time="0.15">
      <error message="kaboom"><![CDATA[NPE at line 7 < 8]]></error>
    </testcase>
  </testsuite>
  <testsuite name="UtilSuite" tests="1" time="0.0">
    <testcase name="pending" classname="Util">
      <skipped/>
    </testcase>
  </testsuite>
</testsuites>`;

  test("normalises every testcase across nested suites", () => {
    const run = parseJUnitXml(xml, "junit.xml");
    expect(run.source).toBe("junit.xml");
    expect(run.cases).toHaveLength(5);

    const byName = Object.fromEntries(run.cases.map((c) => [c.name, c]));

    expect(byName["adds"]).toEqual({
      name: "adds",
      suite: "Math",
      status: "passed",
      durationSeconds: 0.1,
    });
    // A <failure> child => failed, and the message attribute is decoded.
    expect(byName["divides"]?.status).toBe("failed");
    expect(byName["divides"]?.message).toBe("expected 2 & got 3");
    // An <error> child also normalises to failed; CDATA text survives.
    expect(byName["explodes"]?.status).toBe("failed");
    expect(byName["explodes"]?.message).toBe("kaboom");
    // A <skipped/> child => skipped, suite falls back to classname.
    expect(byName["pending"]).toEqual({
      name: "pending",
      suite: "Util",
      status: "skipped",
      durationSeconds: 0,
    });
  });

  test("supports a bare <testsuite> root with no <testsuites> wrapper", () => {
    const bare = `<testsuite name="Solo" tests="1">
      <testcase name="works" classname="Solo" time="0.3"/>
    </testsuite>`;
    const run = parseJUnitXml(bare, "solo.xml");
    expect(run.cases).toHaveLength(1);
    expect(run.cases[0]).toEqual({
      name: "works",
      suite: "Solo",
      status: "passed",
      durationSeconds: 0.3,
    });
  });

  test("falls back to the testsuite name when classname is absent", () => {
    const noClass = `<testsuite name="FallbackSuite">
      <testcase name="t1" time="0.0"/>
    </testsuite>`;
    const run = parseJUnitXml(noClass, "nc.xml");
    expect(run.cases[0]?.suite).toBe("FallbackSuite");
  });

  test("uses the single child testsuite name when <testsuites> has no name", () => {
    const noWrapperName = `<testsuites>
      <testsuite name="OnlySuite">
        <testcase name="t" classname="OnlySuite" time="0.1"/>
      </testsuite>
    </testsuites>`;
    expect(parseJUnitXml(noWrapperName, "x.xml").name).toBe("OnlySuite");
  });

  test("passes an out-of-range numeric character reference through unchanged", () => {
    const weird = `<testsuite name="S">
      <testcase name="t" classname="S" time="0">
        <failure message="bad &#9999999999; ref">boom</failure>
      </testcase>
    </testsuite>`;
    const run = parseJUnitXml(weird, "weird.xml");
    expect(run.cases[0]?.message).toBe("bad &#9999999999; ref");
  });

  test("throws a source-named error on malformed XML", () => {
    expect(() => parseJUnitXml("<testsuite><testcase></testsuite>", "broken.xml")).toThrow(
      /broken\.xml/,
    );
  });
});

describe("parseResultFile", () => {
  test("dispatches on file extension", () => {
    const jsonRun = parseResultFile('{"tests":[{"name":"x","status":"passed"}]}', "a.json");
    expect(jsonRun.cases[0]?.name).toBe("x");

    const xmlRun = parseResultFile(
      '<testsuite name="S"><testcase name="y" classname="S"/></testsuite>',
      "b.xml",
    );
    expect(xmlRun.cases[0]?.name).toBe("y");
  });

  test("rejects unknown extensions with a helpful error", () => {
    expect(() => parseResultFile("whatever", "notes.txt")).toThrow(/notes\.txt/);
  });
});
