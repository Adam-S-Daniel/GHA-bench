/**
 * Domain types for the secret rotation validator.
 *
 * A "secret" is any credential that must be periodically rotated (API keys,
 * DB passwords, signing keys, ...). Each secret carries metadata describing
 * when it was last rotated, how often it must be rotated, and which services
 * depend on it. The validator turns that raw metadata into an urgency-graded
 * rotation report.
 */

/** Urgency buckets, ordered from most to least urgent. */
export type Urgency = "expired" | "warning" | "ok";

/** Raw, user-supplied configuration for a single secret. */
export interface SecretConfig {
  /** Unique, human-readable identifier (e.g. "AWS_ACCESS_KEY"). */
  name: string;
  /** Date the secret was last rotated, as a strict `YYYY-MM-DD` string. */
  lastRotated: string;
  /** Rotation cadence in days. A secret expires `rotationPolicyDays` after `lastRotated`. */
  rotationPolicyDays: number;
  /** Services that depend on this secret (used for blast-radius reporting). */
  requiredBy: string[];
}

/** A secret after evaluation against a reference "now" date. */
export interface SecretStatus extends SecretConfig {
  /** Computed expiry date (`lastRotated` + `rotationPolicyDays`), as `YYYY-MM-DD`. */
  expiryDate: string;
  /** Whole days elapsed since the secret was last rotated. */
  daysSinceRotation: number;
  /** Whole days until expiry. Negative means the secret is already overdue. */
  daysUntilExpiry: number;
  /** Urgency bucket derived from `daysUntilExpiry` and the warning window. */
  urgency: Urgency;
}

/** Evaluated secrets partitioned by urgency. */
export interface UrgencyGroups {
  expired: SecretStatus[];
  warning: SecretStatus[];
  ok: SecretStatus[];
}

/** Aggregate counts for a quick at-a-glance summary. */
export interface ReportSummary {
  total: number;
  expired: number;
  warning: number;
  ok: number;
}

/** The full rotation report produced by {@link buildReport}. */
export interface RotationReport {
  /** The reference "now" date used for the evaluation, as `YYYY-MM-DD`. */
  generatedAt: string;
  /** Warning window (in days) used to classify "warning" vs "ok". */
  warningWindowDays: number;
  /** Aggregate counts. */
  summary: ReportSummary;
  /** Secrets grouped by urgency, each group sorted most-urgent-first. */
  groups: UrgencyGroups;
}

/** Output formats supported by the CLI. */
export type OutputFormat = "markdown" | "json" | "github";
