/**
 * Format parsers. Each parser turns a raw file body into a normalised
 * `TestRun`. Two formats are supported:
 *
 *   - JSON  (`parseJsonResults`)  — a flexible, hand-friendly schema.
 *   - JUnit (`parseJUnitXml`)      — the de-facto CI interchange format.
 *
 * `parseResultFile` dispatches on file extension. All parsers throw an `Error`
 * with a message that names the offending source so the CLI can report which
 * file is bad.
 */
import type { TestCaseResult, TestRun, TestStatus } from "./types";

/**
 * Normalise the many spellings a status can take across tools into our small
 * three-value set. JUnit-style `error` and JSON's `fail`/`failure` all collapse
 * into `failed`; `pending`/`ignored`/`disabled` collapse into `skipped`.
 */
export function normaliseStatus(raw: string): TestStatus {
  const s = raw.trim().toLowerCase();
  switch (s) {
    case "pass":
    case "passed":
    case "success":
    case "ok":
      return "passed";
    case "fail":
    case "failed":
    case "failure":
    case "error":
    case "errored":
      return "failed";
    case "skip":
    case "skipped":
    case "pending":
    case "ignored":
    case "disabled":
      return "skipped";
    default:
      throw new Error(`unrecognised test status: "${raw}"`);
  }
}

/** Coerce an unknown duration field (seconds) into a finite, non-negative number. */
function coerceDuration(value: unknown): number {
  if (value === undefined || value === null) return 0;
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n) || n < 0) return 0;
  return n;
}

interface RawJsonTest {
  name?: unknown;
  suite?: unknown;
  classname?: unknown;
  status?: unknown;
  result?: unknown;
  outcome?: unknown;
  duration?: unknown;
  time?: unknown;
  message?: unknown;
}

/**
 * Parse a JSON results file. Accepted shapes:
 *
 *   { "name": "...", "tests": [ {name,status,...}, ... ] }   // object form
 *   [ {name,status,...}, ... ]                               // bare array form
 *
 * Per-test fields: `name` (required), `suite`/`classname` (optional), one of
 * `status`/`result`/`outcome` (required), `duration`/`time` (optional seconds),
 * and `message` (optional).
 */
export function parseJsonResults(body: string, source: string): TestRun {
  let parsed: unknown;
  try {
    parsed = JSON.parse(body);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`invalid JSON in "${source}": ${reason}`);
  }

  // Accept either the object form (with a `tests` array) or a bare array.
  let runName = "";
  let rawTests: unknown;
  if (Array.isArray(parsed)) {
    rawTests = parsed;
  } else if (parsed && typeof parsed === "object") {
    const obj = parsed as { name?: unknown; tests?: unknown; testcases?: unknown };
    runName = typeof obj.name === "string" ? obj.name : "";
    rawTests = obj.tests ?? obj.testcases;
  }

  if (!Array.isArray(rawTests)) {
    throw new Error(
      `invalid JSON in "${source}": expected a "tests" array or a top-level array of tests`,
    );
  }

  const cases: TestCaseResult[] = rawTests.map((entry, index) => {
    if (!entry || typeof entry !== "object") {
      throw new Error(`invalid test entry at index ${index} in "${source}": not an object`);
    }
    const t = entry as RawJsonTest;

    if (typeof t.name !== "string" || t.name.length === 0) {
      throw new Error(`test at index ${index} in "${source}" is missing a string "name"`);
    }

    const rawStatus = t.status ?? t.result ?? t.outcome;
    if (typeof rawStatus !== "string") {
      throw new Error(`test "${t.name}" in "${source}" is missing a "status"`);
    }

    const suite =
      typeof t.suite === "string" ? t.suite : typeof t.classname === "string" ? t.classname : "";

    const result: TestCaseResult = {
      name: t.name,
      suite,
      status: normaliseStatus(rawStatus),
      durationSeconds: coerceDuration(t.duration ?? t.time),
    };
    if (typeof t.message === "string" && t.message.length > 0) {
      result.message = t.message;
    }
    return result;
  });

  return { source, name: runName, cases };
}

/* ----------------------------------------------------------------------------
 * Minimal XML parser
 *
 * Bun has no built-in XML parser and pulling a dependency would mean a network
 * install inside the CI container, so we ship a small, self-contained recursive
 * parser. It is deliberately scoped to what JUnit needs — elements, attributes,
 * text, CDATA, comments, the XML declaration, and the five predefined entities
 * (plus numeric character references). It is strict enough to reject malformed
 * input (mismatched/unclosed tags) so corrupt files surface as errors.
 * ------------------------------------------------------------------------- */

/** A parsed XML element. `text` holds the element's own concatenated text. */
export interface XmlNode {
  tag: string;
  attrs: Record<string, string>;
  children: XmlNode[];
  text: string;
}

/** Decode the predefined XML entities and numeric character references. */
function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g, (match, body: string) => {
    if (body[0] === "#") {
      const code = body[1] === "x" ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
      // Leave out-of-range / unparseable references untouched rather than
      // throwing a RangeError that would reject the whole file.
      if (Number.isFinite(code) && code >= 0 && code <= 0x10ffff) {
        return String.fromCodePoint(code);
      }
      return match;
    }
    switch (body) {
      case "lt":
        return "<";
      case "gt":
        return ">";
      case "amp":
        return "&";
      case "quot":
        return '"';
      case "apos":
        return "'";
      default:
        return match; // leave unknown entities untouched
    }
  });
}

/** Parse a start/self-closing tag beginning at `xml[start] === "<"`. */
function parseStartTag(
  xml: string,
  start: number,
): { node: XmlNode; next: number; selfClosing: boolean } {
  let i = start + 1;
  const len = xml.length;

  // Tag name: up to whitespace, "/", or ">".
  const nameStart = i;
  while (i < len && !/[\s/>]/.test(xml[i] as string)) i++;
  const tag = xml.slice(nameStart, i);
  if (tag.length === 0) throw new Error(`malformed tag at offset ${start}`);

  const attrs: Record<string, string> = {};
  while (i < len) {
    while (i < len && /\s/.test(xml[i] as string)) i++; // skip whitespace
    if (i >= len) throw new Error(`unterminated tag <${tag}>`);
    if (xml[i] === "/" && xml[i + 1] === ">") {
      return { node: { tag, attrs, children: [], text: "" }, next: i + 2, selfClosing: true };
    }
    if (xml[i] === ">") {
      return { node: { tag, attrs, children: [], text: "" }, next: i + 1, selfClosing: false };
    }

    // Attribute name.
    const attrNameStart = i;
    while (i < len && !/[\s=/>]/.test(xml[i] as string)) i++;
    const attrName = xml.slice(attrNameStart, i);
    if (attrName.length === 0) throw new Error(`malformed attribute in <${tag}>`);

    while (i < len && /\s/.test(xml[i] as string)) i++;
    let value = "";
    if (xml[i] === "=") {
      i++;
      while (i < len && /\s/.test(xml[i] as string)) i++;
      const quote = xml[i];
      if (quote !== '"' && quote !== "'") {
        throw new Error(`expected quoted value for attribute "${attrName}" in <${tag}>`);
      }
      i++;
      const valueStart = i;
      while (i < len && xml[i] !== quote) i++;
      if (i >= len) throw new Error(`unterminated attribute value in <${tag}>`);
      value = decodeEntities(xml.slice(valueStart, i));
      i++; // consume closing quote
    }
    attrs[attrName] = value;
  }
  throw new Error(`unterminated tag <${tag}>`);
}

/** Parse a complete XML document into its single root element. */
export function parseXml(xml: string): XmlNode {
  const len = xml.length;
  let i = 0;
  let root: XmlNode | null = null;
  const stack: XmlNode[] = [];

  const appendText = (raw: string): void => {
    const top = stack[stack.length - 1];
    if (top) top.text += raw;
  };

  while (i < len) {
    if (xml[i] === "<") {
      if (xml.startsWith("<!--", i)) {
        const end = xml.indexOf("-->", i + 4);
        if (end === -1) throw new Error("unterminated comment");
        i = end + 3;
      } else if (xml.startsWith("<![CDATA[", i)) {
        const end = xml.indexOf("]]>", i + 9);
        if (end === -1) throw new Error("unterminated CDATA section");
        appendText(xml.slice(i + 9, end)); // CDATA content is verbatim, no decoding
        i = end + 3;
      } else if (xml.startsWith("<?", i)) {
        const end = xml.indexOf("?>", i + 2);
        if (end === -1) throw new Error("unterminated processing instruction");
        i = end + 2;
      } else if (xml.startsWith("<!", i)) {
        // DOCTYPE or similar declaration — skip to the matching ">".
        const end = xml.indexOf(">", i + 2);
        if (end === -1) throw new Error("unterminated declaration");
        i = end + 1;
      } else if (xml[i + 1] === "/") {
        // Closing tag.
        const end = xml.indexOf(">", i + 2);
        if (end === -1) throw new Error("unterminated closing tag");
        const tag = xml.slice(i + 2, end).trim();
        const open = stack.pop();
        if (!open) throw new Error(`unexpected closing tag </${tag}>`);
        if (open.tag !== tag) {
          throw new Error(`mismatched closing tag: expected </${open.tag}> but found </${tag}>`);
        }
        i = end + 1;
      } else {
        // Opening (possibly self-closing) tag.
        const { node, next, selfClosing } = parseStartTag(xml, i);
        const parent = stack[stack.length - 1];
        if (parent) {
          parent.children.push(node);
        } else if (root) {
          throw new Error(`multiple root elements (<${root.tag}> and <${node.tag}>)`);
        } else {
          root = node;
        }
        if (!selfClosing) stack.push(node);
        i = next;
      }
    } else {
      const next = xml.indexOf("<", i);
      const end = next === -1 ? len : next;
      const chunk = xml.slice(i, end);
      if (chunk.trim().length > 0) appendText(decodeEntities(chunk));
      i = end;
    }
  }

  if (stack.length > 0) {
    throw new Error(`unclosed tag <${stack[stack.length - 1]?.tag}>`);
  }
  if (!root) throw new Error("no root element found");
  return root;
}

/** Depth-first collect every descendant (and self) whose tag matches. */
function collectByTag(node: XmlNode, tag: string, out: XmlNode[] = []): XmlNode[] {
  if (node.tag === tag) out.push(node);
  for (const child of node.children) collectByTag(child, tag, out);
  return out;
}

/**
 * Parse a JUnit XML document. Handles both a `<testsuites>` wrapper and a bare
 * `<testsuite>` root, arbitrarily nested suites, and the standard
 * failure/error/skipped child markers.
 */
export function parseJUnitXml(body: string, source: string): TestRun {
  let root: XmlNode;
  try {
    root = parseXml(body);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`invalid XML in "${source}": ${reason}`);
  }

  // A run name, if the document gives us one. A <testsuites> wrapper often
  // carries no name of its own; when it wraps exactly one <testsuite>, borrow
  // that suite's name so XML runs get a meaningful label like JSON runs do.
  let runName = root.attrs.name ?? "";
  if (runName.length === 0 && root.tag === "testsuites") {
    const childSuites = root.children.filter((c) => c.tag === "testsuite");
    if (childSuites.length === 1) runName = childSuites[0]?.attrs.name ?? "";
  }
  const suites = collectByTag(root, "testsuite");
  // A lone <testsuite> root is itself a suite; collectByTag already includes it.
  // A <testsuites> wrapper contributes only its descendant <testsuite> nodes.

  const cases: TestCaseResult[] = [];
  for (const suite of suites) {
    const suiteName = suite.attrs.name ?? "";
    // Only direct <testcase> children, so nested suites are not double-counted.
    for (const tc of suite.children.filter((c) => c.tag === "testcase")) {
      const name = tc.attrs.name ?? "";
      const className = tc.attrs.classname ?? "";
      const suiteLabel = className.length > 0 ? className : suiteName;

      const failureNode = tc.children.find((c) => c.tag === "failure" || c.tag === "error");
      const skippedNode = tc.children.find((c) => c.tag === "skipped");

      let status: TestStatus;
      let message: string | undefined;
      if (failureNode) {
        status = "failed";
        const attrMsg = failureNode.attrs.message;
        message = attrMsg && attrMsg.length > 0 ? attrMsg : failureNode.text.trim() || undefined;
      } else if (skippedNode) {
        status = "skipped";
        const attrMsg = skippedNode.attrs.message;
        if (attrMsg && attrMsg.length > 0) message = attrMsg;
      } else {
        status = "passed";
      }

      const result: TestCaseResult = {
        name,
        suite: suiteLabel,
        status,
        durationSeconds: coerceDuration(tc.attrs.time),
      };
      if (message) result.message = message;
      cases.push(result);
    }
  }

  return { source, name: runName, cases };
}

/**
 * Parse a result file, dispatching on its extension. `.json` -> JSON format,
 * `.xml` (and `.junit`) -> JUnit XML. Unknown extensions raise a clear error.
 */
export function parseResultFile(body: string, source: string): TestRun {
  const lower = source.toLowerCase();
  if (lower.endsWith(".json")) return parseJsonResults(body, source);
  if (lower.endsWith(".xml") || lower.endsWith(".junit")) return parseJUnitXml(body, source);
  throw new Error(
    `cannot determine format for "${source}": expected a .json or .xml (JUnit) file`,
  );
}
