/**
 * Format parsers: turn raw file contents into a normalized `TestRun`.
 *
 * Two input formats are supported:
 *   - JUnit XML (the `<testsuite>/<testcase>` shape emitted by most runners)
 *   - JSON (a simple `{ tests: [...] }` or bare `[...]` shape)
 *
 * The JUnit parser is intentionally dependency-free: JUnit XML has a small,
 * stable surface, so a focused regex scan over `<testcase>` elements is both
 * sufficient and avoids pulling in an XML library. Each `<testcase>`'s status
 * is inferred from the presence of a child `<failure>`, `<error>`, or
 * `<skipped>` element (absence of all three means the case passed).
 */

import type { TestCase, TestRun, TestStatus } from "./types.ts";

/** Decode the handful of XML entities that appear in attribute values. */
function decodeXmlEntities(value: string): string {
  return value
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

/** Read a named attribute from a raw element tag string. */
function readAttr(tag: string, attr: string): string | undefined {
  const match = tag.match(new RegExp(`\\b${attr}\\s*=\\s*"([^"]*)"`));
  return match ? decodeXmlEntities(match[1]!) : undefined;
}

/**
 * Parse JUnit XML into a `TestRun`. `sourceName` becomes the run name (and is
 * the only thing we need from the filesystem layer, keeping the parser pure).
 */
export function parseJUnitXml(xml: string, sourceName: string): TestRun {
  // Cheap sanity check: a JUnit document must contain at least one testcase or
  // testsuite element. This catches "not XML at all" inputs with a clear error
  // rather than silently returning an empty run.
  if (!/<testcase|<testsuite/i.test(xml)) {
    throw new Error(
      `Failed to parse JUnit XML from "${sourceName}": no <testsuite> or <testcase> elements found`,
    );
  }

  const cases: TestCase[] = [];

  // Match each <testcase ...> element, whether self-closing (<.../>) or with a
  // body (<...>...</testcase>). Group 1 = attributes, group 2 = inner body.
  const caseRe = /<testcase\b([^>]*?)(?:\/>|>([\s\S]*?)<\/testcase\s*>)/gi;

  let match: RegExpExecArray | null;
  while ((match = caseRe.exec(xml)) !== null) {
    const attrs = match[1] ?? "";
    const body = match[2] ?? "";

    const name = readAttr(attrs, "name");
    if (name === undefined) {
      throw new Error(
        `Failed to parse JUnit XML from "${sourceName}": a <testcase> is missing its "name" attribute`,
      );
    }

    // classname is the JUnit convention for the owning suite/class.
    const suite = readAttr(attrs, "classname") ?? "";

    const timeRaw = readAttr(attrs, "time");
    const duration = timeRaw !== undefined ? Number.parseFloat(timeRaw) : 0;

    // Status is determined by the child elements of the case body.
    let status: TestStatus = "passed";
    if (/<failure\b|<error\b/i.test(body)) {
      status = "failed";
    } else if (/<skipped\b/i.test(body)) {
      status = "skipped";
    }

    cases.push({
      name,
      suite,
      status,
      duration: Number.isFinite(duration) ? duration : 0,
    });
  }

  return { name: sourceName, cases };
}

/** Map a free-form status string to our normalized `TestStatus`. */
function normalizeStatus(raw: unknown, sourceName: string): TestStatus {
  const value = String(raw ?? "").trim().toLowerCase();
  switch (value) {
    case "passed":
    case "pass":
    case "ok":
    case "success":
      return "passed";
    case "failed":
    case "fail":
    case "failure":
    case "error":
      return "failed";
    case "skipped":
    case "skip":
    case "pending":
    case "ignored":
      return "skipped";
    default:
      throw new Error(
        `Unknown test status "${raw}" in "${sourceName}". ` +
          `Expected one of: passed, failed, skipped (or common aliases).`,
      );
  }
}

/** Shape of a single test entry in the JSON format (all but name optional). */
interface JsonTestEntry {
  name?: unknown;
  suite?: unknown;
  classname?: unknown;
  status?: unknown;
  duration?: unknown;
  time?: unknown;
}

/**
 * Parse the JSON format into a `TestRun`. Accepts either `{ tests: [...] }` or
 * a bare array of test entries. Status aliases (pass/fail/skip/...) are
 * normalized; an unrecognized status is a hard error so bad data is loud.
 */
export function parseJson(json: string, sourceName: string): TestRun {
  let data: unknown;
  try {
    data = JSON.parse(json);
  } catch (err) {
    throw new Error(
      `Failed to parse JSON from "${sourceName}": ${(err as Error).message}`,
    );
  }

  // Accept both the wrapped ({ tests: [...] }) and bare-array forms.
  const entries: unknown = Array.isArray(data)
    ? data
    : (data as { tests?: unknown })?.tests;

  if (!Array.isArray(entries)) {
    throw new Error(
      `Failed to parse JSON from "${sourceName}": expected an array of tests ` +
        `or an object with a "tests" array.`,
    );
  }

  const cases: TestCase[] = entries.map((raw, index) => {
    const entry = raw as JsonTestEntry;
    const name = entry?.name;
    if (typeof name !== "string" || name.length === 0) {
      throw new Error(
        `Failed to parse JSON from "${sourceName}": test at index ${index} ` +
          `is missing a non-empty "name".`,
      );
    }

    const suite =
      typeof entry.suite === "string"
        ? entry.suite
        : typeof entry.classname === "string"
          ? entry.classname
          : "";

    // Accept either "duration" or "time"; default to 0 when absent.
    const durationRaw = entry.duration ?? entry.time ?? 0;
    const duration = Number(durationRaw);

    return {
      name,
      suite,
      status: normalizeStatus(entry.status, sourceName),
      duration: Number.isFinite(duration) ? duration : 0,
    };
  });

  return { name: sourceName, cases };
}

/**
 * Dispatch to the right parser based on the file extension. This is the entry
 * point the filesystem/CLI layer uses; the per-format parsers stay pure.
 */
export function parseContent(content: string, fileName: string): TestRun {
  const lower = fileName.toLowerCase();
  if (lower.endsWith(".xml")) {
    return parseJUnitXml(content, fileName);
  }
  if (lower.endsWith(".json")) {
    return parseJson(content, fileName);
  }
  throw new Error(
    `Unsupported file format for "${fileName}". Supported extensions: .xml, .json`,
  );
}
