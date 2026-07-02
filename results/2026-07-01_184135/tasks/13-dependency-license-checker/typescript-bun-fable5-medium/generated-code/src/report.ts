import { checkLicense } from "./check";
import type {
  ComplianceReport,
  Dependency,
  LicenseConfig,
  LicenseLookup,
  ReportEntry,
} from "./types";

/**
 * Build a compliance report by resolving each dependency's license through
 * the injected lookup and classifying it against the config. The lookup is
 * a plain function so tests can substitute an in-memory mock.
 */
export function generateReport(
  deps: Dependency[],
  config: LicenseConfig,
  lookup: LicenseLookup,
): ComplianceReport {
  const entries: ReportEntry[] = deps.map((dep) => {
    const license = lookup(dep);
    return { name: dep.name, version: dep.version, license, status: checkLicense(license, config) };
  });
  const count = (status: ReportEntry["status"]): number =>
    entries.filter((e) => e.status === status).length;
  return {
    entries,
    summary: {
      total: entries.length,
      approved: count("approved"),
      denied: count("denied"),
      unknown: count("unknown"),
    },
  };
}

/** Render the report as stable, machine-assertable text. */
export function formatReport(report: ComplianceReport): string {
  const lines: string[] = [
    "Dependency License Compliance Report",
    "====================================",
  ];
  for (const e of report.entries) {
    lines.push(
      `${e.status.toUpperCase()} ${e.name}@${e.version} ${e.license ?? "(license not found)"}`,
    );
  }
  lines.push("------------------------------------");
  const s = report.summary;
  lines.push(
    `Summary: total=${s.total} approved=${s.approved} denied=${s.denied} unknown=${s.unknown}`,
  );
  return lines.join("\n");
}
