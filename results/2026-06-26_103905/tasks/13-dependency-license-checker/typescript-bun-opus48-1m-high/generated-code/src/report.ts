/**
 * Report generation and formatting.
 *
 * generateReport() is the pure core: given dependencies, a license lookup, and
 * a policy, it produces a ComplianceReport. formatReport() renders that report
 * to a deterministic text block with stable lines that CI can assert on.
 */
import { classify } from "./policy.ts";
import type {
  ComplianceEntry,
  ComplianceReport,
  Dependency,
  LicenseLookup,
  LicensePolicy,
} from "./types.ts";

/**
 * Build a compliance report by resolving and classifying each dependency.
 * Order of `entries` mirrors the input order so output is deterministic.
 */
export function generateReport(
  deps: Dependency[],
  lookup: LicenseLookup,
  policy: LicensePolicy,
): ComplianceReport {
  const entries: ComplianceEntry[] = deps.map((dep) => {
    const license = lookup(dep);
    return {
      name: dep.name,
      version: dep.version,
      license,
      status: classify(license, policy),
    };
  });

  const summary = {
    total: entries.length,
    approved: entries.filter((e) => e.status === "approved").length,
    denied: entries.filter((e) => e.status === "denied").length,
    unknown: entries.filter((e) => e.status === "unknown").length,
  };

  // Denied is always a failure; unknown only fails when the policy is strict.
  const compliant =
    summary.denied === 0 && (!policy.failOnUnknown || summary.unknown === 0);

  return { entries, summary, compliant };
}

/** Pad a string to `width` for simple column alignment. */
function pad(value: string, width: number): string {
  return value.length >= width ? value : value + " ".repeat(width - value.length);
}

/**
 * Render a ComplianceReport to a stable, human-readable text block.
 * The exact "Summary:" and "RESULT:" lines are part of the contract that the
 * CI workflow asserts against, so keep their wording stable.
 */
export function formatReport(report: ComplianceReport): string {
  const lines: string[] = [];
  lines.push("Dependency License Compliance Report");
  lines.push("====================================");

  if (report.entries.length === 0) {
    lines.push("(no dependencies found)");
  } else {
    // Compute column widths from the data for tidy alignment.
    const idCol = Math.max(
      ...report.entries.map((e) => `${e.name}@${e.version}`.length),
      "DEPENDENCY".length,
    );
    const licCol = Math.max(
      ...report.entries.map((e) => (e.license ?? "n/a").length),
      "LICENSE".length,
    );

    lines.push(`${pad("DEPENDENCY", idCol)}  ${pad("LICENSE", licCol)}  STATUS`);
    for (const e of report.entries) {
      const id = `${e.name}@${e.version}`;
      const lic = e.license ?? "n/a";
      lines.push(`${pad(id, idCol)}  ${pad(lic, licCol)}  ${e.status.toUpperCase()}`);
    }
  }

  const s = report.summary;
  lines.push("");
  lines.push(
    `Summary: ${s.approved} approved, ${s.denied} denied, ${s.unknown} unknown (${s.total} total)`,
  );
  lines.push(`RESULT: ${report.compliant ? "PASS" : "FAIL"}`);

  return lines.join("\n");
}
