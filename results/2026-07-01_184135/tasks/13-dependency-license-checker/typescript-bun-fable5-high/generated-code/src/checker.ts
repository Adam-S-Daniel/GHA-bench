/**
 * Compliance checking: resolve each dependency's license via a LicenseLookup
 * and classify it against the allow/deny config.
 *
 * Classification rules:
 *  - license on the deny list  -> "denied"  (deny wins over allow)
 *  - license on the allow list -> "approved"
 *  - anything else (including a lookup miss) -> "unknown"
 * All license comparisons are case-insensitive.
 */
import type {
  ComplianceReport,
  Dependency,
  LicenseConfig,
  LicenseLookup,
  LicenseStatus,
  ReportEntry,
} from "./types";

function classify(license: string | null, config: LicenseConfig): LicenseStatus {
  if (license === null) return "unknown";
  const normalized = license.toLowerCase();
  if (config.deny.some((l) => l.toLowerCase() === normalized)) return "denied";
  if (config.allow.some((l) => l.toLowerCase() === normalized)) return "approved";
  return "unknown";
}

/** Check every dependency and build the full compliance report. */
export async function checkCompliance(
  deps: Dependency[],
  config: LicenseConfig,
  lookup: LicenseLookup,
): Promise<ComplianceReport> {
  const entries: ReportEntry[] = [];
  for (const dep of deps) {
    let license: string | null;
    try {
      license = await lookup.getLicense(dep.name, dep.version);
    } catch (err) {
      throw new Error(
        `License lookup failed for ${dep.name}@${dep.version}: ${(err as Error).message}`,
      );
    }
    entries.push({ ...dep, license, status: classify(license, config) });
  }

  const summary = { approved: 0, denied: 0, unknown: 0 };
  for (const entry of entries) summary[entry.status]++;
  return { entries, summary };
}
