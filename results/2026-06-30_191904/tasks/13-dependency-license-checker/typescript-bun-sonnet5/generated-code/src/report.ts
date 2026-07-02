import { classifyLicense } from "./classify";
import type {
  ComplianceReport,
  Dependency,
  LicenseConfig,
  LicenseLookup,
  ReportEntry,
} from "./types";

/** Looks up + classifies every dependency, producing entries and aggregate counts. */
export async function generateReport(
  dependencies: readonly Dependency[],
  lookup: LicenseLookup,
  config: LicenseConfig,
): Promise<ComplianceReport> {
  const entries: ReportEntry[] = [];

  for (const dependency of dependencies) {
    const license = await lookup(dependency);
    const status = classifyLicense(license, config);
    entries.push({ name: dependency.name, version: dependency.version, license, status });
  }

  const summary = {
    total: entries.length,
    approved: entries.filter((e) => e.status === "approved").length,
    denied: entries.filter((e) => e.status === "denied").length,
    unknown: entries.filter((e) => e.status === "unknown").length,
  };

  return { entries, summary };
}

/** Plain-text rendering: one bracketed status line per dependency, then a summary line. */
export function formatReportText(report: ComplianceReport): string {
  const lines = ["Dependency License Compliance Report", "====================================="];

  for (const entry of report.entries) {
    const status = entry.status.toUpperCase();
    const license = entry.license ?? "UNKNOWN";
    lines.push(`[${status}] ${entry.name}@${entry.version} - ${license}`);
  }

  lines.push("");
  const { total, approved, denied, unknown } = report.summary;
  lines.push(`SUMMARY: total=${total} approved=${approved} denied=${denied} unknown=${unknown}`);

  return lines.join("\n");
}

/** Markdown rendering suitable for a GitHub Actions job summary. */
export function formatReportMarkdown(report: ComplianceReport): string {
  const lines = [
    "# Dependency License Compliance Report",
    "",
    "| Dependency | Version | License | Status |",
    "| --- | --- | --- | --- |",
  ];

  for (const entry of report.entries) {
    const license = entry.license ?? "UNKNOWN";
    lines.push(`| ${entry.name} | ${entry.version} | ${license} | ${entry.status} |`);
  }

  const { total, approved, denied, unknown } = report.summary;
  lines.push("");
  lines.push(`**Summary:** total=${total}, approved=${approved}, denied=${denied}, unknown=${unknown}`);

  return lines.join("\n");
}
