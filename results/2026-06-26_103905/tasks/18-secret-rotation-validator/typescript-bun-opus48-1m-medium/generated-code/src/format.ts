// Renderers: turn a RotationReport into either a markdown table or JSON.
import { iterateBySeverity, type RotationReport } from "./report.ts";
import type { SecretEvaluation } from "./validator.ts";

/** A flattened, serialisable view of one evaluated secret. */
interface Notification {
  name: string;
  status: string;
  daysUntilDue: number;
  lastRotated: string;
  rotationPolicyDays: number;
  dueDate: string;
  requiredBy: string[];
}

function toNotification(evaluation: SecretEvaluation): Notification {
  return {
    name: evaluation.secret.name,
    status: evaluation.status,
    daysUntilDue: evaluation.daysUntilDue,
    lastRotated: evaluation.secret.lastRotated,
    rotationPolicyDays: evaluation.secret.rotationPolicyDays,
    dueDate: evaluation.dueDate.toISOString().slice(0, 10),
    requiredBy: evaluation.secret.requiredBy,
  };
}

/** Render the report as a GitHub-flavoured markdown document with a table. */
export function renderMarkdown(report: RotationReport): string {
  const lines: string[] = [];
  lines.push("# Secret Rotation Report");
  lines.push("");
  lines.push(`Generated at: ${report.generatedAt}`);
  lines.push(`Warning window: ${report.warningWindowDays} days`);
  lines.push("");
  lines.push(
    `**Expired:** ${report.summary.expired} | ` +
      `**Warning:** ${report.summary.warning} | ` +
      `**OK:** ${report.summary.ok} | ` +
      `**Total:** ${report.summary.total}`,
  );
  lines.push("");
  lines.push("| Secret | Status | Days Until Due | Last Rotated | Policy (days) | Required By |");
  lines.push("| --- | --- | --- | --- | --- | --- |");

  for (const { evaluation } of iterateBySeverity(report)) {
    const s = evaluation.secret;
    const requiredBy = s.requiredBy.length > 0 ? s.requiredBy.join(", ") : "-";
    lines.push(
      `| ${s.name} | ${evaluation.status} | ${evaluation.daysUntilDue} | ` +
        `${s.lastRotated} | ${s.rotationPolicyDays} | ${requiredBy} |`,
    );
  }

  lines.push("");
  return lines.join("\n");
}

/** Render the report as pretty-printed JSON with notifications grouped by urgency. */
export function renderJson(report: RotationReport): string {
  const payload = {
    generatedAt: report.generatedAt,
    warningWindowDays: report.warningWindowDays,
    hasExpired: report.hasExpired,
    summary: report.summary,
    notifications: {
      expired: report.groups.expired.map(toNotification),
      warning: report.groups.warning.map(toNotification),
      ok: report.groups.ok.map(toNotification),
    },
  };
  return JSON.stringify(payload, null, 2);
}
