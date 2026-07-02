// Parses JUnit-style XML test reports (as emitted by most JS/TS/Python/Java test
// runners) into the normalized TestCase[] shape used by the aggregator.
//
// We avoid a full XML/DOM dependency and instead use targeted regexes, since
// JUnit XML has a small, predictable shape (<testsuites><testsuite><testcase>).

import type { ParsedFile, TestCase, TestStatus } from "../types";

function decodeXmlEntities(value: string): string {
  return value
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

function extractAttr(tag: string, attr: string): string | undefined {
  // Leading \s ensures "name" doesn't match inside "classname".
  const match = tag.match(new RegExp(`[\\s]${attr}="([^"]*)"`));
  return match?.[1] !== undefined ? decodeXmlEntities(match[1]) : undefined;
}

/**
 * Parses a JUnit XML report string into a normalized ParsedFile.
 * @param xml Raw XML content.
 * @param source Label identifying which run this file represents (e.g. its path).
 */
export function parseJUnitXml(xml: string, source: string): ParsedFile {
  try {
    const trimmed = xml.trim();
    if (trimmed.length === 0 || !trimmed.endsWith(">")) {
      throw new Error("Input is not well-formed XML (unterminated tag)");
    }

    const tests: TestCase[] = [];

    // Match each <testcase ...>...</testcase> or self-closing <testcase .../>
    const testCaseRegex = /<testcase\b([^>]*?)(\/>|>([\s\S]*?)<\/testcase>)/g;
    let match: RegExpExecArray | null;
    let foundAny = false;

    while ((match = testCaseRegex.exec(xml)) !== null) {
      foundAny = true;
      const [, attrsStr, , body = ""] = match;
      const openTag = `<testcase ${attrsStr}>`;

      const name = extractAttr(openTag, "name");
      const suite = extractAttr(openTag, "classname") ?? "unknown";
      const timeStr = extractAttr(openTag, "time");
      const duration = timeStr ? parseFloat(timeStr) : 0;

      if (!name) {
        throw new Error("Encountered a <testcase> element without a 'name' attribute");
      }

      let status: TestStatus = "passed";
      let message: string | undefined;

      const failureMatch = body.match(/<failure\b([^>]*)>([\s\S]*?)<\/failure>|<failure\b[^>]*\/>/);
      const errorMatch = body.match(/<error\b([^>]*)>([\s\S]*?)<\/error>|<error\b[^>]*\/>/);
      const skippedMatch = body.match(/<skipped\b[^>]*>[\s\S]*?<\/skipped>|<skipped\b[^>]*\/>/);

      if (failureMatch || errorMatch) {
        status = "failed";
        const failureTag = failureMatch?.[0] ?? errorMatch?.[0] ?? "";
        message = extractAttr(failureTag, "message") ?? decodeXmlEntities(body).trim();
      } else if (skippedMatch) {
        status = "skipped";
      }

      tests.push({ name, suite, status, duration, ...(message ? { message } : {}) });
    }

    if (!foundAny && /<testcase\b/.test(xml) === false && xml.trim().length > 0) {
      // No <testcase> elements found at all; validate this looks like a
      // well-formed (if empty) report rather than garbage input.
      if (!/<testsuites?\b/.test(xml)) {
        throw new Error("No <testsuite> or <testcase> elements found");
      }
    }

    return { source, format: "junit", tests };
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to parse JUnit XML from "${source}": ${reason}`);
  }
}
