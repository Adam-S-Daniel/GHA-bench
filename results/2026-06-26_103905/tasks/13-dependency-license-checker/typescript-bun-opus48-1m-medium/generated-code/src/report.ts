// License lookup source (mockable) and human/machine report formatting.
import type {
  ComplianceReport,
  Dependency,
  LicenseLookup,
} from "./types.ts";

/**
 * Build a license lookup from an in-memory database mapping package name
 * to SPDX license id. This is the deterministic, offline stand-in for a
 * real registry call — used both in tests and in CI where there is no
 * network access. Unknown packages return `undefined`.
 */
export function createDbLookup(
  db: Record<string, string | null>,
): LicenseLookup {
  return (dep: Dependency) => (dep.name in db ? db[dep.name] : undefined);
}

export type ReportFormat = "text" | "json";

/** Render a compliance report as human-readable text or JSON. */
export function formatReport(
  report: ComplianceReport,
  format: ReportFormat,
): string {
  if (format === "json") {
    return JSON.stringify(report, null, 2);
  }

  const lines: string[] = [];
  lines.push("Dependency License Compliance Report");
  lines.push("====================================");

  for (const e of report.entries) {
    const license = e.license ?? "<none>";
    lines.push(
      `- ${e.name}@${e.version}  license=${license}  status=${e.status.toUpperCase()}`,
    );
  }

  const s = report.summary;
  lines.push("------------------------------------");
  lines.push(
    `Total: ${s.total}  Approved: ${s.approved}  Denied: ${s.denied}  Unknown: ${s.unknown}`,
  );
  lines.push(`Verdict: ${s.compliant ? "COMPLIANT" : "NOT COMPLIANT"}`);

  return lines.join("\n");
}
