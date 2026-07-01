// Core domain types for the secret rotation validator.

/** Raw secret metadata as loaded from a config JSON file. */
export interface Secret {
  name: string;
  lastRotated: string; // ISO date string, e.g. "2026-01-01"
  rotationPolicyDays: number;
  requiredBy: string[];
}

/** Urgency classification for a secret relative to "now" and a warning window. */
export type UrgencyLevel = "expired" | "warning" | "ok";

/** Computed rotation status for a single secret. */
export interface RotationStatus {
  secret: Secret;
  daysSinceRotation: number;
  daysUntilExpiry: number;
  expiryDate: string; // ISO date string
  urgency: UrgencyLevel;
}

/** Secrets grouped by urgency level. */
export interface GroupedStatuses {
  expired: RotationStatus[];
  warning: RotationStatus[];
  ok: RotationStatus[];
}

/** Options controlling how a report is generated. */
export interface ReportOptions {
  now: Date;
  warningDays: number;
  format: OutputFormat;
}

export type OutputFormat = "markdown" | "json";
