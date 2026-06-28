// Shared domain types for the dependency license checker.

/** A single dependency extracted from a manifest. */
export interface Dependency {
  name: string;
  /** Raw version specifier, e.g. "^1.3.0", "4.17.21", or "*" when unpinned. */
  version: string;
}

/** Supported manifest formats. */
export type ManifestType = "package.json" | "requirements.txt";

/** License allow/deny configuration provided by the caller. */
export interface LicenseConfig {
  /** Licenses that are explicitly approved (SPDX-style identifiers). */
  allow: string[];
  /** Licenses that are explicitly forbidden. */
  deny: string[];
}

/** Outcome of evaluating a single dependency's license. */
export type LicenseStatus = "approved" | "denied" | "unknown";

/**
 * A license lookup function. In production this would query a registry;
 * in tests it is mocked. Returns the SPDX license id, or `null`/`undefined`
 * when the license cannot be determined.
 */
export type LicenseLookup = (
  dep: Dependency,
) => string | null | undefined;

/** One row of the compliance report. */
export interface ComplianceEntry {
  name: string;
  version: string;
  license: string | null;
  status: LicenseStatus;
}

/** Aggregate compliance report. */
export interface ComplianceReport {
  entries: ComplianceEntry[];
  summary: {
    total: number;
    approved: number;
    denied: number;
    unknown: number;
    /** True when no dependency is denied or unknown. */
    compliant: boolean;
  };
}
