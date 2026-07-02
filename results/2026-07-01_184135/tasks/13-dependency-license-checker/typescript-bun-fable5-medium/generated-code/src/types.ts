/**
 * Shared types for the dependency license checker.
 */

/** A single dependency extracted from a manifest. */
export interface Dependency {
  name: string;
  version: string;
}

/** Allow/deny license configuration (SPDX identifiers). */
export interface LicenseConfig {
  allow: string[];
  deny: string[];
}

/** Compliance status of a dependency's license. */
export type LicenseStatus = "approved" | "denied" | "unknown";

/**
 * Resolves a dependency to its license (SPDX id), or undefined if unknown.
 * Injected into the report generator so tests can supply a mock.
 */
export type LicenseLookup = (dep: Dependency) => string | undefined;

/** One row of the compliance report. */
export interface ReportEntry {
  name: string;
  version: string;
  license: string | undefined;
  status: LicenseStatus;
}

/** The full compliance report. */
export interface ComplianceReport {
  entries: ReportEntry[];
  summary: {
    total: number;
    approved: number;
    denied: number;
    unknown: number;
  };
}
