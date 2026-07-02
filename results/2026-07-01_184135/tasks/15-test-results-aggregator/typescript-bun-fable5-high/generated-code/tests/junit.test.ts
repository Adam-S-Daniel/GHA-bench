/**
 * TDD Cycle 1 — JUnit XML parser.
 *
 * RED: written before src/parsers/junit.ts existed; every test failed with a
 * module-resolution error. GREEN: minimal parser implemented to satisfy these
 * cases, then refactored (attribute parsing extracted to a helper).
 */
import { describe, expect, test } from "bun:test";
import { parseJUnitXml } from "../src/parsers/junit";

const SAMPLE = `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="auth" tests="4" failures="1" skipped="1" time="2.0">
    <testcase classname="auth" name="test_login" time="0.5" />
    <testcase classname="auth" name="test_logout" time="0.3"></testcase>
    <testcase classname="auth" name="test_flaky_network" time="1.2">
      <failure message="connection reset by peer">stack trace here</failure>
    </testcase>
    <testcase classname="auth" name="test_skipped" time="0">
      <skipped message="not implemented" />
    </testcase>
  </testsuite>
</testsuites>`;

describe("parseJUnitXml", () => {
  test("parses every <testcase> element", () => {
    const run = parseJUnitXml(SAMPLE, "shard1.xml");
    expect(run.source).toBe("shard1.xml");
    expect(run.cases).toHaveLength(4);
  });

  test("maps passing, failing and skipped cases to statuses", () => {
    const run = parseJUnitXml(SAMPLE, "shard1.xml");
    const byName = Object.fromEntries(run.cases.map((c) => [c.name, c]));
    expect(byName["test_login"]).toEqual({
      suite: "auth",
      name: "test_login",
      status: "passed",
      durationSeconds: 0.5,
    });
    expect(byName["test_flaky_network"]?.status).toBe("failed");
    expect(byName["test_flaky_network"]?.message).toBe("connection reset by peer");
    expect(byName["test_skipped"]?.status).toBe("skipped");
  });

  test("supports <error> children as failures", () => {
    const xml = `<testsuite name="s"><testcase classname="s" name="boom" time="0.1"><error message="oops"/></testcase></testsuite>`;
    const run = parseJUnitXml(xml, "e.xml");
    expect(run.cases[0]?.status).toBe("failed");
    expect(run.cases[0]?.message).toBe("oops");
  });

  test("decodes XML entities in attributes", () => {
    const xml = `<testsuite name="s"><testcase classname="a &amp; b" name="x &lt; y" time="0.2"/></testsuite>`;
    const run = parseJUnitXml(xml, "e.xml");
    expect(run.cases[0]?.suite).toBe("a & b");
    expect(run.cases[0]?.name).toBe("x < y");
  });

  test("treats a missing time attribute as 0 seconds", () => {
    const xml = `<testsuite name="s"><testcase classname="s" name="quick"/></testsuite>`;
    const run = parseJUnitXml(xml, "e.xml");
    expect(run.cases[0]?.durationSeconds).toBe(0);
  });

  test("throws a meaningful error for content without any <testcase>", () => {
    expect(() => parseJUnitXml("<html></html>", "bad.xml")).toThrow(
      /bad\.xml.*no <testcase> elements/i,
    );
  });

  test("throws a meaningful error when a testcase is missing its name", () => {
    const xml = `<testsuite><testcase classname="s" time="1"/></testsuite>`;
    expect(() => parseJUnitXml(xml, "bad.xml")).toThrow(/bad\.xml.*missing.*name/i);
  });
});
