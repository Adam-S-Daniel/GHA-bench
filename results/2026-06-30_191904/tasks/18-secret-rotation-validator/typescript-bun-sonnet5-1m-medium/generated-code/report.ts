// Formats a RotationReport as either markdown (for GH Actions job summaries)
// or JSON (for machine consumption).

import type { OutputFormat, RotationReport, SecretStatus } from "./types.ts";

function renderTable(title: string, secrets: SecretStatus[]): string {
  const lines: string[] = [`## ${title} (${secrets.length})`];

  if (secrets.length === 0) {
    lines.push("_none_");
    return lines.join("\n");
  }

  lines.push("| Secret | Days Until Expiry | Last Rotated | Policy (days) | Required By |");
  lines.push("| --- | --- | --- | --- | --- |");
  for (const secret of secrets) {
    lines.push(
      `| ${secret.name} | ${secret.daysUntilExpiry} | ${secret.lastRotated} | ${secret.rotationPolicyDays} | ${secret.requiredBy.join(", ")} |`,
    );
  }
  return lines.join("\n");
}

function toMarkdown(report: RotationReport): string {
  return [
    "# Secret Rotation Report",
    "",
    `Generated: ${report.generatedAt}  `,
    `Warning window: ${report.warningWindowDays} day(s)`,
    "",
    renderTable("Expired", report.expired),
    "",
    renderTable("Warning", report.warning),
    "",
    renderTable("OK", report.ok),
    "",
  ].join("\n");
}

/** Formats a rotation report in the requested output format. */
export function formatReport(report: RotationReport, format: OutputFormat): string {
  switch (format) {
    case "json":
      return JSON.stringify(report, null, 2);
    case "markdown":
      return toMarkdown(report);
    default:
      throw new Error(`Unsupported output format: ${format as string}`);
  }
}
