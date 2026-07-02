import type { ParsedFile, TestCaseResult } from "./types";

// Minimal JUnit XML parser. We avoid pulling in a full XML library since the
// JUnit <testsuite>/<testcase> shape we need to support is narrow and regex
// based extraction keeps the dependency footprint at zero.

function extractAttr(tag: string, attr: string): string | undefined {
  const match = tag.match(new RegExp(`${attr}="([^"]*)"`));
  return match ? match[1] : undefined;
}

export function parseJUnitXml(xml: string, source: string): ParsedFile {
  if (!xml.includes("<testsuite") || !xml.includes("</testsuite>")) {
    throw new Error(`Failed to parse malformed JUnit XML in "${source}": missing <testsuite> root element`);
  }

  const suiteOpenTagMatch = xml.match(/<testsuite\b[^>]*>/);
  const suiteName = suiteOpenTagMatch ? extractAttr(suiteOpenTagMatch[0], "name") ?? "unknown" : "unknown";

  const tests: TestCaseResult[] = [];
  const testcaseRegex = /<testcase\b([^>]*?)(\/>|>([\s\S]*?)<\/testcase>)/g;
  let match: RegExpExecArray | null;

  while ((match = testcaseRegex.exec(xml)) !== null) {
    const attrsStr = `<testcase ${match[1]}>`;
    const body = match[3] ?? "";

    const name = extractAttr(attrsStr, "name") ?? "unnamed test";
    const classname = extractAttr(attrsStr, "classname") ?? suiteName;
    const time = parseFloat(extractAttr(attrsStr, "time") ?? "0");

    let status: TestCaseResult["status"] = "passed";
    let message: string | undefined;

    if (/<failure\b/.test(body) || /<error\b/.test(body)) {
      status = "failed";
      const failureTagMatch = body.match(/<(failure|error)\b([^>]*)\/?>/);
      const attrMessage = failureTagMatch ? extractAttr(failureTagMatch[0], "message") : undefined;
      const bodyTextMatch = body.match(/<(?:failure|error)\b[^>]*>([\s\S]*?)<\/(?:failure|error)>/);
      message = attrMessage ?? bodyTextMatch?.[1]?.trim();
    } else if (/<skipped\b/.test(body)) {
      status = "skipped";
    }

    tests.push({
      name,
      suite: classname,
      status,
      duration: isNaN(time) ? 0 : time,
      message,
    });
  }

  return { source, tests };
}
