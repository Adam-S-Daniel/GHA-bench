// Formats a ComplianceReport for human consumption (CI logs) or machine
// consumption (downstream tooling / artifacts).

import type { ComplianceReport } from "./types";

export function formatReportText(report: ComplianceReport): string {
  const lines: string[] = ["Dependency License Compliance Report", "====================================="];

  for (const result of report.results) {
    const license = result.license ?? "UNKNOWN";
    lines.push(`${result.name}@${result.version}: ${license} [${result.status.toUpperCase()}]`);
  }

  lines.push("-------------------------------------");
  lines.push(`Total: ${report.summary.total}`);
  lines.push(`Approved: ${report.summary.approved}`);
  lines.push(`Denied: ${report.summary.denied}`);
  lines.push(`Unknown: ${report.summary.unknown}`);

  return lines.join("\n");
}

export function formatReportJson(report: ComplianceReport): string {
  return JSON.stringify(report, null, 2);
}
