/**
 * Rendering of a {@link RotationReport} into the supported output formats.
 *
 * Formatters are pure string functions so they can be unit-tested without any
 * file or process I/O.
 */
import type { RotationReport, SecretStatus, OutputFormat, Urgency } from "./types";

/** JSON: the full report, pretty-printed for human + machine consumption. */
export function toJSON(report: RotationReport): string {
  return JSON.stringify(report, null, 2);
}

/**
 * GitHub Actions step outputs: `key=value` lines suitable for appending to
 * `$GITHUB_OUTPUT`. Kept to the four summary counters that downstream jobs
 * gate on.
 */
export function toGitHubOutput(report: RotationReport): string {
  const { total, expired, warning, ok } = report.summary;
  return [`total=${total}`, `expired=${expired}`, `warning=${warning}`, `ok=${ok}`].join("\n");
}

// --- markdown helpers -------------------------------------------------------

const TABLE_HEADER =
  "| Secret | Last Rotated | Expires | Days Left | Policy (days) | Required By |";
const TABLE_DIVIDER = "| --- | --- | --- | --- | --- | --- |";

/** Render one secret as a markdown table row. */
function renderRow(s: SecretStatus): string {
  const requiredBy = s.requiredBy.length > 0 ? s.requiredBy.join(", ") : "—";
  return `| ${s.name} | ${s.lastRotated} | ${s.expiryDate} | ${s.daysUntilExpiry} | ${s.rotationPolicyDays} | ${requiredBy} |`;
}

/** Render a single urgency section: a header plus a table (or a placeholder). */
function renderSection(title: string, secrets: SecretStatus[]): string {
  const heading = `## ${title} (${secrets.length})`;
  if (secrets.length === 0) {
    return `${heading}\n\n_None._`;
  }
  const rows = secrets.map(renderRow).join("\n");
  return `${heading}\n\n${TABLE_HEADER}\n${TABLE_DIVIDER}\n${rows}`;
}

/** Human-facing section title for each urgency bucket. */
const SECTION_TITLE: Record<Urgency, string> = {
  expired: "Expired",
  warning: "Warning",
  ok: "OK",
};

/**
 * Markdown: an urgency-grouped report. Suitable for posting directly to a
 * GitHub Actions job summary (`$GITHUB_STEP_SUMMARY`). The most urgent section
 * comes first so a reader sees the expired secrets immediately.
 */
export function toMarkdown(report: RotationReport): string {
  const { total, expired, warning, ok } = report.summary;
  const header = [
    "# Secret Rotation Report",
    "",
    `- Reference date: ${report.generatedAt}`,
    `- Warning window: ${report.warningWindowDays} days`,
    `- Secrets: ${total} total · ${expired} expired · ${warning} warning · ${ok} ok`,
  ].join("\n");

  const sections = (["expired", "warning", "ok"] as Urgency[]).map((u) =>
    renderSection(SECTION_TITLE[u], report.groups[u]),
  );

  return [header, ...sections].join("\n\n") + "\n";
}

/** Dispatch to the formatter matching the requested {@link OutputFormat}. */
export function formatReport(report: RotationReport, format: OutputFormat): string {
  switch (format) {
    case "json":
      return toJSON(report);
    case "markdown":
      return toMarkdown(report);
    case "github":
      return toGitHubOutput(report);
    default: {
      // Exhaustiveness guard: if a new format is added to the union but not
      // handled here, TypeScript flags this branch at compile time.
      const exhaustive: never = format;
      throw new Error(`Unsupported output format: ${String(exhaustive)}`);
    }
  }
}
