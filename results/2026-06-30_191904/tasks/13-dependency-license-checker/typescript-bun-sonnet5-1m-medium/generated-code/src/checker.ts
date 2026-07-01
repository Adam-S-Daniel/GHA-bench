// Checks each dependency's license against an allow/deny policy and produces
// a compliance report with an aggregated summary.

import type { LicenseLookup } from "./licenseLookup";
import type { ComplianceReport, ComplianceResult, Dependency, LicensePolicy, LicenseStatus } from "./types";

function classify(license: string | null, policy: LicensePolicy): LicenseStatus {
  if (license === null) return "unknown";
  if (policy.deny.includes(license)) return "denied";
  if (policy.allow.includes(license)) return "approved";
  return "unknown";
}

export async function checkCompliance(
  deps: Dependency[],
  lookup: LicenseLookup,
  policy: LicensePolicy
): Promise<ComplianceReport> {
  const results: ComplianceResult[] = [];

  for (const dep of deps) {
    const license = await lookup.lookup(dep);
    results.push({
      name: dep.name,
      version: dep.version,
      license,
      status: classify(license, policy),
    });
  }

  const summary = {
    total: results.length,
    approved: results.filter((r) => r.status === "approved").length,
    denied: results.filter((r) => r.status === "denied").length,
    unknown: results.filter((r) => r.status === "unknown").length,
  };

  return { results, summary };
}
