// Shared domain types for the dependency license checker.

export interface Dependency {
  name: string;
  version: string;
}

export interface LicensePolicy {
  allow: string[];
  deny: string[];
}

export type LicenseStatus = "approved" | "denied" | "unknown";

export interface ComplianceResult {
  name: string;
  version: string;
  license: string | null;
  status: LicenseStatus;
}

export interface ComplianceReport {
  results: ComplianceResult[];
  summary: {
    total: number;
    approved: number;
    denied: number;
    unknown: number;
  };
}
