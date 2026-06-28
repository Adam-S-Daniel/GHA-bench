/**
 * Parsers that normalise the supported test-result file formats into the
 * shared {@link TestRun} shape.
 *
 * Supported formats:
 *   - JUnit XML  (`.xml`) — the de-facto standard most test runners emit.
 *   - JSON       (`.json`) — a simple, flexible schema (see parseJsonResults).
 *
 * The JUnit parser is intentionally a small, dependency-free reader rather
 * than a full XML DOM: JUnit reports have a narrow, well-known structure, so a
 * focused tokenizer keeps the tool dependency-free (important for running it in
 * an isolated CI container with no `bun install`).
 */
import type { TestCase, TestRun, TestStatus } from "./types.ts";

/** Decode the five predefined XML entities found in JUnit messages. */
function decodeXmlEntities(text: string): string {
  return text
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

/** Pull every `name="value"` / `name='value'` pair out of an attribute string. */
function parseAttributes(attrText: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  const re = /([\w:.-]+)\s*=\s*("([^"]*)"|'([^']*)')/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(attrText)) !== null) {
    const value = m[3] !== undefined ? m[3] : (m[4] ?? "");
    attrs[m[1]!] = decodeXmlEntities(value);
  }
  return attrs;
}

/**
 * Extract a failure/error message from a `<testcase>` body. JUnit puts the
 * reason either in a `message="..."` attribute or in the element's text body;
 * we prefer the attribute and fall back to trimmed text content.
 */
function extractMessage(body: string, tag: "failure" | "error"): string | undefined {
  const re = new RegExp(
    `<${tag}\\b([^>]*?)(?:/>|>([\\s\\S]*?)</${tag}>)`,
    "i",
  );
  const m = re.exec(body);
  if (!m) return undefined;
  const attrs = parseAttributes(m[1] ?? "");
  if (attrs.message) return attrs.message;
  const text = (m[2] ?? "").trim();
  return text ? decodeXmlEntities(text) : undefined;
}

/**
 * Parse a JUnit XML document into a {@link TestRun}.
 *
 * Handles both `<testsuites>`-wrapped and bare `<testsuite>` documents,
 * self-closing testcases, and `<failure>`/`<error>`/`<skipped>` children.
 */
export function parseJUnitXml(xml: string, source: string): TestRun {
  const cases: TestCase[] = [];

  // Match either a self-closing <testcase .../> or <testcase ...>body</testcase>.
  const caseRe = /<testcase\b([^>]*?)(?:\/>|>([\s\S]*?)<\/testcase\s*>)/gi;
  let match: RegExpExecArray | null;
  while ((match = caseRe.exec(xml)) !== null) {
    const attrs = parseAttributes(match[1] ?? "");
    const body = match[2] ?? "";

    // Status precedence: error/failure -> failed, else skipped, else passed.
    let status: TestStatus = "passed";
    let message: string | undefined;
    if (/<error\b/i.test(body)) {
      status = "failed";
      message = extractMessage(body, "error");
    } else if (/<failure\b/i.test(body)) {
      status = "failed";
      message = extractMessage(body, "failure");
    } else if (/<skipped\b/i.test(body)) {
      status = "skipped";
    }

    const time = Number.parseFloat(attrs.time ?? "");
    cases.push({
      name: attrs.name ?? "(unnamed)",
      suite: attrs.classname || attrs.suite || undefined,
      status,
      duration: Number.isFinite(time) ? time : 0,
      ...(message ? { message } : {}),
    });
  }

  if (cases.length === 0) {
    throw new Error(
      `Invalid JUnit XML in "${source}": no <testcase> elements found.`,
    );
  }
  return { source, cases };
}

/** Map the many spellings real tools use onto our three canonical statuses. */
function normaliseStatus(raw: string, source: string): TestStatus {
  const s = raw.trim().toLowerCase();
  if (["passed", "pass", "ok", "success", "successful"].includes(s)) return "passed";
  if (["failed", "fail", "failure", "error", "errored", "broken"].includes(s)) return "failed";
  if (["skipped", "skip", "pending", "ignored", "disabled"].includes(s)) return "skipped";
  throw new Error(`Unknown test status "${raw}" in "${source}".`);
}

/** A loosely-typed test record as it may appear in a JSON results file. */
interface RawJsonCase {
  name?: string;
  suite?: string;
  classname?: string;
  status?: string;
  result?: string;
  outcome?: string;
  duration?: number | string;
  time?: number | string;
  message?: string;
}

function coerceDuration(value: number | string | undefined): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  if (typeof value === "string") {
    const n = Number.parseFloat(value);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

/**
 * Parse a JSON results document into a {@link TestRun}.
 *
 * Accepts either a top-level array of cases, or an object with a `tests`
 * (or `testcases`/`cases`/`results`) array and an optional `name`. Status,
 * duration and suite fields each accept a few common synonyms so the tool is
 * forgiving of the many JSON shapes test runners emit.
 */
export function parseJsonResults(json: string, source: string): TestRun {
  let data: unknown;
  try {
    data = JSON.parse(json);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to parse JSON in "${source}": ${reason}`);
  }

  let rawCases: RawJsonCase[];
  let runName = source;
  if (Array.isArray(data)) {
    rawCases = data as RawJsonCase[];
  } else if (data && typeof data === "object") {
    const obj = data as Record<string, unknown>;
    if (typeof obj.name === "string") runName = obj.name;
    const list = obj.tests ?? obj.testcases ?? obj.cases ?? obj.results;
    if (!Array.isArray(list)) {
      throw new Error(
        `Invalid JSON results in "${source}": expected an array or an object ` +
          `with a "tests" array.`,
      );
    }
    rawCases = list as RawJsonCase[];
  } else {
    throw new Error(
      `Invalid JSON results in "${source}": expected an array or object.`,
    );
  }

  const cases: TestCase[] = rawCases.map((raw, i) => {
    const rawStatus = raw.status ?? raw.result ?? raw.outcome;
    if (typeof rawStatus !== "string") {
      throw new Error(
        `Invalid JSON results in "${source}": case #${i + 1} is missing a status.`,
      );
    }
    const suite = raw.suite || raw.classname || undefined;
    const duration = coerceDuration(raw.duration ?? raw.time);
    return {
      name: raw.name ?? `(unnamed #${i + 1})`,
      ...(suite ? { suite } : {}),
      status: normaliseStatus(rawStatus, source),
      duration,
      ...(raw.message ? { message: raw.message } : {}),
    };
  });

  return { source: runName, cases };
}

/** Dispatch to the right parser based on the file extension of `source`. */
export function parseContent(content: string, source: string): TestRun {
  const lower = source.toLowerCase();
  if (lower.endsWith(".xml")) return parseJUnitXml(content, source);
  if (lower.endsWith(".json")) return parseJsonResults(content, source);
  throw new Error(
    `Unsupported result format for "${source}": expected a .xml or .json file.`,
  );
}

/** Read a result file from disk and parse it. */
export async function parseFile(path: string): Promise<TestRun> {
  const file = Bun.file(path);
  let content: string;
  try {
    if (!(await file.exists())) {
      throw new Error("file not found");
    }
    content = await file.text();
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Could not read result file "${path}": ${reason}`);
  }
  // Use just the file name as the default source label.
  const name = path.split("/").pop() ?? path;
  return parseContent(content, name);
}
