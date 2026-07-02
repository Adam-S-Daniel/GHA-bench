/**
 * TDD cycle 1 (RED): JUnit XML parser.
 *
 * The parser must handle:
 *  - <testsuites> root wrapping multiple <testsuite> elements
 *  - a bare <testsuite> root
 *  - <failure>, <error> (both count as failed) and <skipped> children
 *  - XML entity decoding in attributes
 *  - malformed input -> descriptive error
 */
import { describe, expect, test } from "bun:test";
import { parseJUnitXml } from "../src/junit";

const SUITES_XML = `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="auth" tests="3" failures="1" skipped="1" time="1.5">
    <testcase classname="auth" name="logs in" time="0.5"/>
    <testcase classname="auth" name="rejects bad &lt;password&gt;" time="0.7">
      <failure message="expected 401 got 500">stack trace here</failure>
    </testcase>
    <testcase classname="auth" name="oauth flow" time="0.3">
      <skipped/>
    </testcase>
  </testsuite>
  <testsuite name="cart" tests="1" time="0.2">
    <testcase classname="cart" name="adds item" time="0.2"/>
  </testsuite>
</testsuites>`;

describe("parseJUnitXml", () => {
  test("parses a <testsuites> document into normalized cases", () => {
    const result = parseJUnitXml(SUITES_XML, "junit-ubuntu.xml");
    expect(result.source).toBe("junit-ubuntu.xml");
    expect(result.cases).toHaveLength(4);

    expect(result.cases[0]).toEqual({
      suite: "auth",
      name: "logs in",
      status: "passed",
      durationSec: 0.5,
    });
    // entity decoding + failure message captured
    expect(result.cases[1]).toEqual({
      suite: "auth",
      name: "rejects bad <password>",
      status: "failed",
      durationSec: 0.7,
      message: "expected 401 got 500",
    });
    expect(result.cases[2]!.status).toBe("skipped");
    expect(result.cases[3]).toEqual({
      suite: "cart",
      name: "adds item",
      status: "passed",
      durationSec: 0.2,
    });
  });

  test("parses a bare <testsuite> root", () => {
    const xml = `<testsuite name="solo" tests="1">
      <testcase classname="solo" name="works" time="0.1"/>
    </testsuite>`;
    const result = parseJUnitXml(xml, "solo.xml");
    expect(result.cases).toHaveLength(1);
    expect(result.cases[0]!.suite).toBe("solo");
  });

  test("treats <error> children as failures", () => {
    const xml = `<testsuite name="s"><testcase classname="s" name="boom" time="0">
      <error message="NullPointerException"/>
    </testcase></testsuite>`;
    const result = parseJUnitXml(xml, "err.xml");
    expect(result.cases[0]!.status).toBe("failed");
    expect(result.cases[0]!.message).toBe("NullPointerException");
  });

  test("defaults missing time/classname gracefully", () => {
    const xml = `<testsuite name="fallback"><testcase name="no attrs"/></testsuite>`;
    const result = parseJUnitXml(xml, "min.xml");
    expect(result.cases[0]).toEqual({
      suite: "fallback",
      name: "no attrs",
      status: "passed",
      durationSec: 0,
    });
  });

  test("throws a descriptive error for non-JUnit input", () => {
    expect(() => parseJUnitXml("<html></html>", "web.xml")).toThrow(
      /web\.xml.*no <testsuite> or <testcase> elements/i,
    );
  });
});
