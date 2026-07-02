// Shared types for the dependency license checker.

/** A single dependency extracted from a manifest file. */
export interface Dependency {
  name: string;
  version: string;
}

/** Config describing which licenses are approved or forbidden. */
export interface LicenseConfig {
  allowList: string[];
  denyList: string[];
}

/** Possible compliance outcomes for a dependency's license. */
export type LicenseStatus = "approved" | "denied" | "unknown";

/** A function that resolves a dependency to its license identifier (e.g. "MIT"). */
export type LicenseLookup = (dep: Dependency) => Promise<string | null>;

/** One row of the compliance report. */
export interface ComplianceEntry {
  name: string;
  version: string;
  license: string | null;
  status: LicenseStatus;
}

/** The full compliance report. */
export interface ComplianceReport {
  entries: ComplianceEntry[];
  summary: {
    total: number;
    approved: number;
    denied: number;
    unknown: number;
  };
}
