import type { ComplianceReport } from "./types";

/** Renders a ComplianceReport as a human-readable plain-text table + summary. */
export function formatReport(report: ComplianceReport): string {
  const lines: string[] = ["Dependency License Compliance Report", "====================================="];

  for (const entry of report.entries) {
    const license = entry.license ?? "UNKNOWN LICENSE";
    lines.push(`${entry.name}@${entry.version} - ${license} - ${entry.status.toUpperCase()}`);
  }

  lines.push("");
  lines.push("Summary:");
  lines.push(`Total: ${report.summary.total}`);
  lines.push(`Approved: ${report.summary.approved}`);
  lines.push(`Denied: ${report.summary.denied}`);
  lines.push(`Unknown: ${report.summary.unknown}`);

  return lines.join("\n");
}
