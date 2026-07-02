/**
 * Shared domain types for the dependency license checker.
 */

/** A single dependency extracted from a manifest, ecosystem-agnostic. */
export interface Dependency {
  name: string;
  version: string;
}

/** Compliance status of one dependency after checking its license. */
export type LicenseStatus = "approved" | "denied" | "unknown";

/** Allow/deny license lists, supplied by the user as JSON config. */
export interface LicenseConfig {
  /** SPDX identifiers that are explicitly approved (e.g. "MIT"). */
  allow: string[];
  /** SPDX identifiers that are explicitly forbidden (e.g. "GPL-3.0"). */
  deny: string[];
}

/** One row of the compliance report. */
export interface ReportEntry {
  name: string;
  version: string;
  /** Resolved license, or null when the lookup could not identify one. */
  license: string | null;
  status: LicenseStatus;
}

/** The full compliance report: per-dependency rows plus aggregate counts. */
export interface ComplianceReport {
  entries: ReportEntry[];
  summary: { approved: number; denied: number; unknown: number };
}

/**
 * Abstraction over "where do licenses come from". Production code can back
 * this with a registry client; tests inject an in-memory mock.
 */
export interface LicenseLookup {
  /** Returns the SPDX license for a package, or null when unknown. */
  getLicense(name: string, version: string): Promise<string | null>;
}
