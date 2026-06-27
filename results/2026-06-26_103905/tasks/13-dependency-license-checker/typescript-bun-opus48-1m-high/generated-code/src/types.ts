/**
 * Shared domain types for the dependency license checker.
 *
 * Keeping these in one place makes the data flow explicit:
 *   manifest text -> Dependency[] -> (lookup license) -> ComplianceEntry[] -> report
 */

/** A single dependency extracted from a manifest, with a normalized version. */
export interface Dependency {
  name: string;
  version: string;
}

/** Supported manifest formats. */
export type ManifestType = "package.json" | "requirements.txt";

/**
 * The compliance verdict for a dependency:
 *  - "approved": license is on the allow-list
 *  - "denied":   license is on the deny-list
 *  - "unknown":  license could not be determined, or is on neither list
 */
export type ComplianceStatus = "approved" | "denied" | "unknown";

/**
 * License policy configuration. `allow` and `deny` are lists of SPDX-style
 * license identifiers (compared case-insensitively). `failOnUnknown` controls
 * whether unknown licenses cause a non-zero exit / failing report.
 */
export interface LicensePolicy {
  allow: string[];
  deny: string[];
  failOnUnknown?: boolean;
}

/**
 * A license lookup resolves a dependency to its license identifier.
 * Returns `null` when the license cannot be determined. This is the seam that
 * is mocked in tests (and fed from a static JSON database in CI).
 */
export type LicenseLookup = (dep: Dependency) => string | null;

/** One row of the compliance report. */
export interface ComplianceEntry {
  name: string;
  version: string;
  /** The resolved license id, or null if unknown. */
  license: string | null;
  status: ComplianceStatus;
}

/** The full compliance report: per-dependency rows plus an aggregate summary. */
export interface ComplianceReport {
  entries: ComplianceEntry[];
  summary: {
    total: number;
    approved: number;
    denied: number;
    unknown: number;
  };
  /** Overall pass/fail: fails if any denied (or unknown when failOnUnknown). */
  compliant: boolean;
}
