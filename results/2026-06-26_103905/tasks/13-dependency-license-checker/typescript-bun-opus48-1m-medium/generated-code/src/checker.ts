// License classification and compliance report generation.
import type {
  ComplianceEntry,
  ComplianceReport,
  Dependency,
  LicenseConfig,
  LicenseLookup,
  LicenseStatus,
} from "./types.ts";

/**
 * Classify a single license string against the allow/deny config.
 *
 * Rules:
 *  - A missing/null license is always "unknown".
 *  - The deny-list takes precedence over the allow-list (fail safe).
 *  - Matching is case-insensitive on the SPDX identifier.
 *  - Anything on neither list is "unknown".
 */
export function classifyLicense(
  license: string | null | undefined,
  config: LicenseConfig,
): LicenseStatus {
  if (license === null || license === undefined || license.trim() === "") {
    return "unknown";
  }

  const normalized = license.trim().toLowerCase();
  const deny = config.deny.map((l) => l.toLowerCase());
  const allow = config.allow.map((l) => l.toLowerCase());

  if (deny.includes(normalized)) return "denied";
  if (allow.includes(normalized)) return "approved";
  return "unknown";
}

/**
 * Build a compliance report for a list of dependencies.
 *
 * @param deps   Dependencies to evaluate.
 * @param lookup License lookup (mockable) returning an SPDX id or null/undefined.
 * @param config Allow/deny configuration.
 */
export function generateReport(
  deps: Dependency[],
  lookup: LicenseLookup,
  config: LicenseConfig,
): ComplianceReport {
  const entries: ComplianceEntry[] = deps.map((dep) => {
    // Normalize "not found" (undefined) and "found but unlicensed" (null)
    // to a single null so the report has a consistent shape.
    const license = lookup(dep) ?? null;
    return {
      name: dep.name,
      version: dep.version,
      license,
      status: classifyLicense(license, config),
    };
  });

  const summary = {
    total: entries.length,
    approved: entries.filter((e) => e.status === "approved").length,
    denied: entries.filter((e) => e.status === "denied").length,
    unknown: entries.filter((e) => e.status === "unknown").length,
    compliant: false,
  };
  // Compliant only when nothing is denied or unknown.
  summary.compliant = summary.denied === 0 && summary.unknown === 0;

  return { entries, summary };
}
