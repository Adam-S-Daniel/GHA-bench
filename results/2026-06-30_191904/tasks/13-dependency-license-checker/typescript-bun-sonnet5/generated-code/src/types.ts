// Shared types for the dependency license checker.

/** A single dependency extracted from a manifest file. */
export interface Dependency {
  readonly name: string;
  readonly version: string;
}

/** Result of comparing a dependency's license against the configured policy. */
export type ComplianceStatus = "approved" | "denied" | "unknown";

/** Allow/deny policy for SPDX-style license identifiers. */
export interface LicenseConfig {
  readonly allowlist: readonly string[];
  readonly denylist: readonly string[];
}

/** One row of the compliance report. */
export interface ReportEntry {
  readonly name: string;
  readonly version: string;
  readonly license: string | null;
  readonly status: ComplianceStatus;
}

/** Aggregate counts across all report entries. */
export interface ReportSummary {
  readonly total: number;
  readonly approved: number;
  readonly denied: number;
  readonly unknown: number;
}

/** Full compliance report: per-dependency entries plus totals. */
export interface ComplianceReport {
  readonly entries: readonly ReportEntry[];
  readonly summary: ReportSummary;
}

/**
 * Resolves the license for a dependency. In production this would call out to a
 * package registry (npm, PyPI, ...); tests and CI both inject a mock/offline
 * implementation so results are deterministic.
 */
export type LicenseLookup = (dependency: Dependency) => Promise<string | null>;
