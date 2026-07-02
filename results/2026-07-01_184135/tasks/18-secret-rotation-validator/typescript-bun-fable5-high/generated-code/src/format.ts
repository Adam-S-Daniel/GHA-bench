/**
 * Output formatters: notifications grouped by urgency.
 *
 * markdown — human-readable notification view (one section per bucket).
 * json     — machine-readable full report, pretty-printed.
 */
import type { RotationReport, SecretStatus, Urgency } from "./types";
import { URGENCIES } from "./types";

export type OutputFormat = "markdown" | "json";
export const OUTPUT_FORMATS: readonly OutputFormat[] = ["markdown", "json"];

/** Render the notification sections as a markdown document. */
export function formatMarkdown(report: RotationReport): string {
  const lines: string[] = [
    "# Secret Rotation Report",
    "",
    `_Reference date: ${report.referenceDate} · Warning window: ${report.warningWindowDays} days_`,
    "",
  ];

  for (const urgency of URGENCIES) {
    const bucket = report.groups[urgency];
    lines.push(`## ${urgency.toUpperCase()} (${bucket.length})`, "");
    if (bucket.length === 0) {
      lines.push("_None_", "");
      continue;
    }
    lines.push(
      "| Secret | Last Rotated | Policy (days) | Expires On | Days Until Expiry | Required By |",
      "| --- | --- | --- | --- | --- | --- |",
      ...bucket.map(tableRow),
      "",
    );
  }
  return lines.join("\n");
}

function tableRow({ secret, expiresOn, daysUntilExpiry }: SecretStatus): string {
  const services = secret.requiredBy.join(", ") || "—";
  return `| ${secret.name} | ${secret.lastRotated} | ${secret.rotationPolicyDays} | ${expiresOn} | ${daysUntilExpiry} | ${services} |`;
}

/** Render the full report as pretty-printed JSON. */
export function formatJson(report: RotationReport): string {
  return JSON.stringify(report, null, 2);
}

/** Dispatch on the format name; errors list what is supported. */
export function formatReport(report: RotationReport, format: OutputFormat): string {
  switch (format) {
    case "markdown":
      return formatMarkdown(report);
    case "json":
      return formatJson(report);
    default:
      throw new Error(
        `unknown format "${format satisfies never}" (supported: ${OUTPUT_FORMATS.join(", ")})`,
      );
  }
}
