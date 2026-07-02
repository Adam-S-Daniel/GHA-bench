import type {
  ComplianceEntry,
  ComplianceReport,
  Dependency,
  LicenseConfig,
  LicenseLookup,
} from "./types";

function classify(license: string | null, config: LicenseConfig): ComplianceEntry["status"] {
  if (!license) return "unknown";
  const normalized = license.toLowerCase();
  if (config.denyList.some((l) => l.toLowerCase() === normalized)) return "denied";
  if (config.allowList.some((l) => l.toLowerCase() === normalized)) return "approved";
  return "unknown";
}

/**
 * Looks up each dependency's license and classifies it against the allow/deny lists,
 * producing a full compliance report with a summary count.
 */
export async function generateComplianceReport(
  deps: Dependency[],
  config: LicenseConfig,
  lookup: LicenseLookup
): Promise<ComplianceReport> {
  const entries: ComplianceEntry[] = [];

  for (const dep of deps) {
    let license: string | null;
    try {
      license = await lookup(dep);
    } catch (err) {
      throw new Error(
        `Failed to look up license for ${dep.name}@${dep.version}: ${(err as Error).message}`
      );
    }
    entries.push({
      name: dep.name,
      version: dep.version,
      license,
      status: classify(license, config),
    });
  }

  const summary = {
    total: entries.length,
    approved: entries.filter((e) => e.status === "approved").length,
    denied: entries.filter((e) => e.status === "denied").length,
    unknown: entries.filter((e) => e.status === "unknown").length,
  };

  return { entries, summary };
}
