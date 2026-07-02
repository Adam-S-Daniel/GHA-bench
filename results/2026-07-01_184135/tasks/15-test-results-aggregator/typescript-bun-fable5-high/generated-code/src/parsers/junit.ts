/**
 * JUnit XML parser.
 *
 * Approach: JUnit reports are flat and highly regular — every test is a
 * `<testcase>` element whose outcome is encoded by an optional child
 * (`<failure>`, `<error>`, `<skipped>`). Instead of pulling in a full XML
 * dependency, we scan for `<testcase ...>` elements (self-closing or paired)
 * with a small regex-based extractor. This deliberately supports the JUnit
 * subset only; anything without `<testcase>` elements is rejected with a
 * clear error rather than silently producing an empty run.
 */
import type { TestCaseResult, TestRun, TestStatus } from "../types";

/** Decode the XML entities that commonly appear in JUnit attribute values. */
function decodeEntities(value: string): string {
  return value
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, code: string) => String.fromCharCode(Number(code)))
    .replace(/&amp;/g, "&"); // last, so we don't double-decode e.g. &amp;lt;
}

/** Parse `key="value"` attribute pairs from an XML tag's attribute string. */
function parseAttributes(attrText: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  for (const m of attrText.matchAll(/([\w:-]+)\s*=\s*"([^"]*)"/g)) {
    attrs[m[1]!] = decodeEntities(m[2]!);
  }
  return attrs;
}

/**
 * Matches one `<testcase .../>` (self-closing) or `<testcase ...>...</testcase>`
 * (paired) element. Group 1: attributes, group 2: inner XML (paired form only).
 */
const TESTCASE_RE = /<testcase\b([^>]*?)(?:\/>|>([\s\S]*?)<\/testcase>)/g;

/** Extract status + failure message from a testcase's child elements. */
function interpretChildren(inner: string): { status: TestStatus; message?: string } {
  const child = inner.match(/<(failure|error|skipped)\b([^>]*?)(?:\/>|>)/);
  if (!child) return { status: "passed" };
  const attrs = parseAttributes(child[2] ?? "");
  const status: TestStatus = child[1] === "skipped" ? "skipped" : "failed";
  return attrs["message"] !== undefined ? { status, message: attrs["message"] } : { status };
}

/**
 * Parse a JUnit XML document into a TestRun.
 *
 * @param xml    Raw XML content.
 * @param source Label for error messages and run identity (usually the file name).
 * @throws Error with the source name when the content has no testcases or a
 *         testcase is malformed.
 */
export function parseJUnitXml(xml: string, source: string): TestRun {
  const cases: TestCaseResult[] = [];

  for (const match of xml.matchAll(TESTCASE_RE)) {
    const attrs = parseAttributes(match[1] ?? "");
    const inner = match[2] ?? "";

    const name = attrs["name"];
    if (name === undefined || name === "") {
      throw new Error(`${source}: <testcase> is missing a "name" attribute`);
    }

    const time = attrs["time"] === undefined || attrs["time"] === "" ? 0 : Number(attrs["time"]);
    if (Number.isNaN(time)) {
      throw new Error(`${source}: testcase "${name}" has a non-numeric time "${attrs["time"]}"`);
    }

    const { status, message } = interpretChildren(inner);
    cases.push({
      suite: attrs["classname"] ?? "(no suite)",
      name,
      status,
      durationSeconds: time,
      ...(message !== undefined ? { message } : {}),
    });
  }

  if (cases.length === 0) {
    throw new Error(
      `${source}: no <testcase> elements found — is this really a JUnit XML report?`,
    );
  }

  return { source, cases };
}
