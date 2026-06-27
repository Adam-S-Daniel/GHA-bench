// Output formatters for a RotationReport.
//
// Two formats are supported, selected by the CLI --format flag:
//   - "json":     machine-readable, stable shape for downstream tooling
//   - "markdown": a human-friendly report with one table per urgency group,
//                 suitable for a GitHub Actions job summary or PR comment.

import type {
  EvaluatedSecret,
  RotationReport,
  RotationStatus,
} from "./validator.ts";

/** Supported output formats. */
export type OutputFormat = "markdown" | "json";

/** Serialize the report as pretty-printed JSON. */
export function formatJson(report: RotationReport): string {
  return JSON.stringify(report, null, 2);
}

/** Human-readable label + emoji per urgency, for the markdown headings. */
const STATUS_META: Record<RotationStatus, { label: string; icon: string }> = {
  expired: { label: "Expired", icon: "🔴" },
  warning: { label: "Warning", icon: "🟡" },
  ok: { label: "OK", icon: "🟢" },
};

/** Escape pipe characters so values never break the markdown table layout. */
function escapeCell(value: string): string {
  return value.replace(/\|/g, "\\|");
}

/** Render one urgency group as a markdown section with a table (or a stub). */
function renderGroup(
  status: RotationStatus,
  secrets: EvaluatedSecret[],
): string {
  const { label, icon } = STATUS_META[status];
  const lines: string[] = [`## ${label} (${secrets.length}) ${icon}`, ""];

  if (secrets.length === 0) {
    lines.push("_None_", "");
    return lines.join("\n");
  }

  lines.push(
    "| Secret | Last Rotated | Policy (days) | Expires On | Days Left | Required By |",
    "| --- | --- | --- | --- | --- | --- |",
  );
  for (const s of secrets) {
    const requiredBy = s.requiredBy.length > 0 ? s.requiredBy.join(", ") : "—";
    lines.push(
      `| ${escapeCell(s.name)} | ${s.lastRotated} | ${s.rotationPolicyDays} | ` +
        `${s.expiresOn} | ${s.daysUntilExpiry} | ${escapeCell(requiredBy)} |`,
    );
  }
  lines.push("");
  return lines.join("\n");
}

/** Render the full report as markdown. */
export function formatMarkdown(report: RotationReport): string {
  const { summary } = report;
  const parts: string[] = [
    "# Secret Rotation Report",
    "",
    `Generated: ${report.generatedAt} · Warning window: ${report.warningWindowDays} days`,
    "",
    "## Summary",
    "",
    `- ${STATUS_META.expired.icon} Expired: ${summary.expired}`,
    `- ${STATUS_META.warning.icon} Warning: ${summary.warning}`,
    `- ${STATUS_META.ok.icon} OK: ${summary.ok}`,
    `- Total: ${summary.total}`,
    "",
    renderGroup("expired", report.groups.expired),
    renderGroup("warning", report.groups.warning),
    renderGroup("ok", report.groups.ok),
  ];
  return parts.join("\n").trimEnd() + "\n";
}

/**
 * Dispatch to the requested formatter. Throws on an unknown format so the CLI
 * can report exactly which value was rejected.
 */
export function formatReport(
  report: RotationReport,
  format: OutputFormat,
): string {
  switch (format) {
    case "json":
      return formatJson(report);
    case "markdown":
      return formatMarkdown(report);
    default:
      throw new Error(
        `Unknown output format '${format}'. Supported formats: markdown, json`,
      );
  }
}
