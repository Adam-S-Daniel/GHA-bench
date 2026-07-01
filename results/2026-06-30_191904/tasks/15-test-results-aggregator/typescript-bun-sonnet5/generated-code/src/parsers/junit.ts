import type { TestCase, TestSuiteResult, TestStatus } from "../types";

/** Decode the small set of XML entities that appear in JUnit report text/attributes. */
function decodeXmlEntities(value: string): string {
  return value
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&apos;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, "&");
}

/**
 * Pulls one attribute value (e.g. name="foo") out of a tag's raw attribute string.
 * Uses a word boundary so looking up "name" doesn't match inside "classname".
 */
function getAttribute(attrs: string, name: string): string | undefined {
  const match = attrs.match(new RegExp(`\\b${name}="([^"]*)"`));
  return match ? decodeXmlEntities(match[1] ?? "") : undefined;
}

/**
 * Minimal parser for the JUnit XML test report format. It targets the common
 * subset produced by most test runners (testsuite > testcase > failure/skipped)
 * rather than being a general-purpose XML parser.
 */
export function parseJUnitXml(xml: string, source: string): TestSuiteResult {
  const suiteMatch = xml.match(/<testsuite\b([^>]*)>/);
  if (!suiteMatch) {
    throw new Error(
      `Failed to parse JUnit XML from "${source}": no <testsuite> element found`,
    );
  }

  if (!xml.includes("</testsuite>")) {
    throw new Error(
      `Failed to parse JUnit XML from "${source}": missing closing </testsuite> tag (malformed XML)`,
    );
  }

  const suiteName = getAttribute(suiteMatch[1] ?? "", "name") ?? "unknown";
  const tests: TestCase[] = [];

  // Match self-closing <testcase .../> or paired <testcase ...>...</testcase>.
  const testcaseRegex = /<testcase\b([^>]*?)(\/>|>([\s\S]*?)<\/testcase>)/g;
  const openTagCount = (xml.match(/<testcase\b/g) ?? []).length;
  let match: RegExpExecArray | null;

  while ((match = testcaseRegex.exec(xml)) !== null) {
    const attrs = match[1] ?? "";
    const body = match[3] ?? "";

    const name = getAttribute(attrs, "name");
    if (!name) {
      throw new Error(
        `Failed to parse JUnit XML from "${source}": <testcase> missing required "name" attribute`,
      );
    }
    const classname = getAttribute(attrs, "classname") ?? "";
    const timeAttr = getAttribute(attrs, "time");
    const duration = timeAttr ? Number.parseFloat(timeAttr) : 0;

    let status: TestStatus = "passed";
    let message: string | undefined;

    const failureMatch = body.match(/<(failure|error)\b([^>]*)(\/>|>([\s\S]*?)<\/\1>)/);
    const skippedMatch = body.match(/<skipped\b([^>]*)\/?>/);

    if (failureMatch) {
      status = "failed";
      message = getAttribute(failureMatch[2] ?? "", "message") ?? decodeXmlEntities((failureMatch[4] ?? "").trim());
    } else if (skippedMatch) {
      status = "skipped";
    }

    const testCase: TestCase = { name, classname, status, duration };
    if (message) {
      testCase.message = message;
    }
    tests.push(testCase);
  }

  if (tests.length !== openTagCount) {
    throw new Error(
      `Failed to parse JUnit XML from "${source}": found ${openTagCount} <testcase> tag(s) but only ${tests.length} were well-formed (malformed XML)`,
    );
  }

  return { suiteName, source, tests };
}
