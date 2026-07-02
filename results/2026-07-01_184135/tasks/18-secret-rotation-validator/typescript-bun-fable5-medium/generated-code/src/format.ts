/**
 * Output formatting: render a RotationReport as a markdown document or as
 * machine-readable JSON. Both group notifications by urgency.
 */
import type { RotationReport, SecretStatus, Urgency } from "./types";

/** "1 day" / "32 days" — keeps notification text grammatical. */
function days(n: number): string {
  return `${n} day${n === 1 ? "" : "s"}`;
}

/**
 * One human-readable notification line for a classified secret.
 * The urgency drives both tone and the suggested action.
 */
export function buildNotification(status: SecretStatus): string {
  const { secret, expiresOn, daysUntilExpiry } = status;
  const requiredBy = `Required by: ${secret.requiredBy.join(", ")}.`;
  switch (status.status) {
    case "expired": {
      const when =
        daysUntilExpiry === 0
          ? `EXPIRES TODAY (${expiresOn})`
          : `EXPIRED ${days(-daysUntilExpiry)} ago on ${expiresOn}`;
      return `Secret "${secret.name}" ${when} — rotate immediately! ${requiredBy}`;
    }
    case "warning":
      return `Secret "${secret.name}" expires in ${days(daysUntilExpiry)} on ${expiresOn} — schedule a rotation. ${requiredBy}`;
    case "ok":
      return `Secret "${secret.name}" is healthy; next rotation due ${expiresOn} (${days(daysUntilExpiry)}). ${requiredBy}`;
  }
}

const URGENCIES: Urgency[] = ["expired", "warning", "ok"];
const ICONS: Record<Urgency, string> = {
  expired: "🔴",
  warning: "🟡",
  ok: "🟢",
};

/** Render one urgency bucket as a markdown section with a table. */
function markdownSection(urgency: Urgency, statuses: SecretStatus[]): string {
  const title = urgency.charAt(0).toUpperCase() + urgency.slice(1);
  const lines: string[] = [
    `## ${ICONS[urgency]} ${title} (${statuses.length})`,
    "",
  ];
  if (statuses.length === 0) {
    lines.push("_None_");
    return lines.join("\n");
  }
  lines.push(
    "| Secret | Last Rotated | Policy (days) | Expires On | Days Until Expiry | Required By |",
    "| --- | --- | --- | --- | --- | --- |",
  );
  for (const s of statuses) {
    lines.push(
      `| ${s.secret.name} | ${s.secret.lastRotated} | ${s.secret.rotationPolicyDays} | ${s.expiresOn} | ${s.daysUntilExpiry} | ${s.secret.requiredBy.join(", ")} |`,
    );
  }
  lines.push("", ...statuses.map((s) => `- ${buildNotification(s)}`));
  return lines.join("\n");
}

/** Full markdown report: header, summary, then one section per bucket. */
export function formatMarkdown(report: RotationReport): string {
  const parts: string[] = [
    "# Secret Rotation Report",
    "",
    `Generated for **${report.generatedFor}** (warning window: ${report.warningWindowDays} days)`,
    "",
    `**Summary:** ${report.expired.length} expired, ${report.warning.length} warning, ${report.ok.length} ok`,
    "",
  ];
  for (const urgency of URGENCIES) {
    parts.push(markdownSection(urgency, report[urgency]), "");
  }
  return parts.join("\n").trimEnd() + "\n";
}

/** JSON shape for one notification entry. */
interface NotificationEntry {
  name: string;
  lastRotated: string;
  rotationPolicyDays: number;
  expiresOn: string;
  daysUntilExpiry: number;
  requiredBy: string[];
  message: string;
}

function toEntry(status: SecretStatus): NotificationEntry {
  return {
    name: status.secret.name,
    lastRotated: status.secret.lastRotated,
    rotationPolicyDays: status.secret.rotationPolicyDays,
    expiresOn: status.expiresOn,
    daysUntilExpiry: status.daysUntilExpiry,
    requiredBy: status.secret.requiredBy,
    message: buildNotification(status),
  };
}

/** Machine-readable report: counts plus notifications grouped by urgency. */
export function formatJson(report: RotationReport): string {
  const payload = {
    generatedFor: report.generatedFor,
    warningWindowDays: report.warningWindowDays,
    summary: {
      expired: report.expired.length,
      warning: report.warning.length,
      ok: report.ok.length,
    },
    notifications: {
      expired: report.expired.map(toEntry),
      warning: report.warning.map(toEntry),
      ok: report.ok.map(toEntry),
    },
  };
  return JSON.stringify(payload, null, 2);
}
