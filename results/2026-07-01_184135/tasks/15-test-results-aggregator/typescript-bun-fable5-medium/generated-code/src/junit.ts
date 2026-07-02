/**
 * JUnit XML parser.
 *
 * Approach: JUnit reports are a small, flat XML dialect (<testsuites> ->
 * <testsuite> -> <testcase> with optional <failure>/<error>/<skipped>
 * children). Rather than pull in a full XML dependency, we walk the document
 * with a scanner that understands just enough XML: elements, attributes and
 * entity decoding. Each <testcase> is normalized into a `TestCaseResult`.
 */
import type { TestCaseResult, TestFileResult, TestStatus } from "./types";

const ENTITIES: Record<string, string> = {
  "&lt;": "<",
  "&gt;": ">",
  "&quot;": '"',
  "&apos;": "'",
  "&amp;": "&",
};

/** Decode the five predefined XML entities plus numeric character refs. */
function decodeEntities(value: string): string {
  return value
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex: string) =>
      String.fromCodePoint(parseInt(hex, 16)),
    )
    .replace(/&#(\d+);/g, (_, dec: string) =>
      String.fromCodePoint(parseInt(dec, 10)),
    )
    .replace(/&(lt|gt|quot|apos|amp);/g, (m) => ENTITIES[m] ?? m);
}

/** Parse `key="value"` attribute pairs from an element's tag body. */
function parseAttributes(tagBody: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  const re = /([\w:.-]+)\s*=\s*"([^"]*)"|([\w:.-]+)\s*=\s*'([^']*)'/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(tagBody)) !== null) {
    const key = m[1] ?? m[3]!;
    const raw = m[2] ?? m[4] ?? "";
    attrs[key] = decodeEntities(raw);
  }
  return attrs;
}

interface RawElement {
  attrs: Record<string, string>;
  /** Inner XML for non-self-closing elements ("" when self-closing). */
  inner: string;
}

/**
 * Extract all top-level occurrences of `tag` inside `xml`.
 * Handles both `<tag .../>` and `<tag ...>...</tag>` forms. JUnit never
 * nests a tag inside itself, so a non-greedy match to the closing tag is safe.
 */
function extractElements(xml: string, tag: string): RawElement[] {
  const out: RawElement[] = [];
  const re = new RegExp(
    `<${tag}(?=[\\s/>])([^>]*?)(/>|>([\\s\\S]*?)</${tag}\\s*>)`,
    "g",
  );
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) {
    out.push({ attrs: parseAttributes(m[1] ?? ""), inner: m[3] ?? "" });
  }
  return out;
}

/** Determine a test case's status from its child elements. */
function caseStatus(inner: string): { status: TestStatus; message?: string } {
  // <failure> and <error> both mean the test did not pass.
  const failure =
    extractElements(inner, "failure")[0] ?? extractElements(inner, "error")[0];
  if (failure) {
    const message = failure.attrs["message"];
    return message !== undefined
      ? { status: "failed", message }
      : { status: "failed" };
  }
  if (extractElements(inner, "skipped").length > 0) {
    return { status: "skipped" };
  }
  return { status: "passed" };
}

/**
 * Parse a JUnit XML document into a normalized `TestFileResult`.
 *
 * @param xml    Raw XML text (either <testsuites> or <testsuite> root).
 * @param source Label for error messages and the result (e.g. file path).
 * @throws Error when the document contains no recognizable JUnit elements.
 */
export function parseJUnitXml(xml: string, source: string): TestFileResult {
  const suites = extractElements(xml, "testsuite");
  if (suites.length === 0) {
    throw new Error(
      `Failed to parse "${source}" as JUnit XML: no <testsuite> or <testcase> elements found`,
    );
  }

  const cases: TestCaseResult[] = [];
  for (const suite of suites) {
    const suiteName = suite.attrs["name"] ?? "(unnamed suite)";
    for (const tc of extractElements(suite.inner, "testcase")) {
      const { status, message } = caseStatus(tc.inner);
      const durationSec = Number.parseFloat(tc.attrs["time"] ?? "0") || 0;
      const result: TestCaseResult = {
        suite: tc.attrs["classname"] ?? suiteName,
        name: tc.attrs["name"] ?? "(unnamed test)",
        status,
        durationSec,
      };
      if (message !== undefined) result.message = message;
      cases.push(result);
    }
  }
  return { source, cases };
}
