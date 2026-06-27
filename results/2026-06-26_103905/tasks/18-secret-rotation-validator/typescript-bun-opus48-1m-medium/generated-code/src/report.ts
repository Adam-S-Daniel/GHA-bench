// Rendering of a RotationReport into the supported output formats.
import type { RotationReport, SecretStatus, Urgency } from "./types";

/** Supported output formats. */
export type OutputFormat = "markdown" | "json";

/** Human-friendly titles for each urgency bucket. */
const URGENCY_TITLE: Record<Urgency, string> = {
  expired: "Expired",
  warning: "Warning",
  ok: "OK",
};

/** Render the report as pretty-printed JSON. */
export function renderJson(report: RotationReport): string {
  return JSON.stringify(report, null, 2);
}

/** Render a single secret status as a markdown table row. */
function tableRow(s: SecretStatus): string {
  const date = s.lastRotated.slice(0, 10); // YYYY-MM-DD
  return `| ${s.name} | ${s.urgency} | ${date} | ${s.rotationPolicyDays} | ${s.daysUntilExpiry} | ${s.requiredBy.join(", ")} |`;
}

/** Render a markdown table for a list of secret statuses. */
function table(statuses: SecretStatus[]): string {
  const header =
    "| Secret | Urgency | Last Rotated | Policy (days) | Days Until Expiry | Required By |";
  const divider = "| --- | --- | --- | --- | --- | --- |";
  const rows = statuses.map(tableRow);
  return [header, divider, ...rows].join("\n");
}

/**
 * Render the report as a markdown document: a summary line, a full table,
 * and a per-urgency section grouping the affected secrets.
 */
export function renderMarkdown(report: RotationReport): string {
  const lines: string[] = [];
  lines.push("# Secret Rotation Report");
  lines.push("");
  lines.push(`Generated at: ${report.generatedAt}`);
  lines.push(`Warning window: ${report.warningWindowDays} days`);
  lines.push("");
  lines.push(
    `**Total:** ${report.summary.total} | **Expired:** ${report.summary.expired} | **Warning:** ${report.summary.warning} | **OK:** ${report.summary.ok}`,
  );
  lines.push("");
  lines.push(table(report.secrets));
  lines.push("");

  // One section per urgency bucket, in most-urgent-first order.
  (["expired", "warning", "ok"] as const).forEach((bucket) => {
    const items = report.byUrgency[bucket];
    lines.push(`## ${URGENCY_TITLE[bucket]} (${items.length})`);
    lines.push("");
    if (items.length === 0) {
      lines.push("_None_");
    } else {
      for (const s of items) {
        const detail =
          s.daysUntilExpiry < 0
            ? `overdue by ${Math.abs(s.daysUntilExpiry)} day(s)`
            : s.daysUntilExpiry === 0
              ? "due today"
              : `${s.daysUntilExpiry} day(s) left`;
        lines.push(`- **${s.name}** — ${detail}; required by ${s.requiredBy.join(", ")}`);
      }
    }
    lines.push("");
  });

  return lines.join("\n").trimEnd() + "\n";
}

/** Dispatch rendering based on the requested output format. */
export function renderReport(
  report: RotationReport,
  format: OutputFormat,
): string {
  switch (format) {
    case "json":
      return renderJson(report);
    case "markdown":
      return renderMarkdown(report);
    default:
      throw new Error(`Unknown output format: "${format}"`);
  }
}
