// Renders a RotationReport as either a markdown table or JSON.
import type { RotationReport, SecretStatus } from "./types.ts";

const TABLE_HEADER: string =
  "| Name | Last Rotated | Policy (days) | Days Until Expiry | Required By |";
const TABLE_DIVIDER: string = "| --- | --- | --- | --- | --- |";

function formatRow(status: SecretStatus): string {
  const requiredBy: string = status.requiredBy.join(", ");
  return `| ${status.name} | ${status.lastRotated} | ${status.rotationPolicyDays} | ${status.daysUntilExpiry} | ${requiredBy} |`;
}

function formatSection(title: string, statuses: SecretStatus[]): string {
  const heading: string = `## ${title} (${statuses.length})`;
  if (statuses.length === 0) {
    return `${heading}\n\n_None_`;
  }
  const rows: string = statuses.map(formatRow).join("\n");
  return `${heading}\n\n${TABLE_HEADER}\n${TABLE_DIVIDER}\n${rows}`;
}

/** Renders the report as a human-readable markdown document. */
export function formatMarkdown(report: RotationReport): string {
  const sections: string[] = [
    "# Secret Rotation Report",
    "",
    `Generated: ${report.generatedAt}`,
    `Warning window: ${report.warningWindowDays} days`,
    `Total secrets: ${report.totalSecrets}`,
    "",
    formatSection("Expired", report.expired),
    "",
    formatSection("Warning", report.warning),
    "",
    formatSection("OK", report.ok),
  ];
  return sections.join("\n");
}

/** Renders the report as pretty-printed JSON, grouped by urgency. */
export function formatJson(report: RotationReport): string {
  return JSON.stringify(report, null, 2);
}

/** Dispatches to the requested output format. */
export function formatReport(report: RotationReport, format: "markdown" | "json"): string {
  return format === "json" ? formatJson(report) : formatMarkdown(report);
}
