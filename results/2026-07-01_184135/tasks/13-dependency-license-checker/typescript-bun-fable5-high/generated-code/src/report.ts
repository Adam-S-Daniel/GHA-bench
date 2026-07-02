/**
 * Report rendering: turn a ComplianceReport into deterministic plain text.
 * The format is stable on purpose — CI pipelines assert on these exact lines.
 */
import type { ComplianceReport } from "./types";

const HEADER = "License Compliance Report";

/** Render the report as text: header, one row per dependency, summary. */
export function formatReport(report: ComplianceReport): string {
  const lines: string[] = [HEADER, "=".repeat(HEADER.length)];

  if (report.entries.length === 0) {
    lines.push("No dependencies found.");
  } else {
    for (const e of report.entries) {
      lines.push(`${e.name}@${e.version}: ${e.license ?? "UNKNOWN"} [${e.status}]`);
    }
  }

  const s = report.summary;
  lines.push(`Summary: ${s.approved} approved, ${s.denied} denied, ${s.unknown} unknown`);
  return lines.join("\n");
}
