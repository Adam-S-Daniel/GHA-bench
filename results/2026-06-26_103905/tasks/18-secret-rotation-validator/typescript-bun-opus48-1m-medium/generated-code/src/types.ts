// Shared type definitions for the secret-rotation validator.

/** Urgency buckets a secret can fall into, ordered most -> least urgent. */
export type Urgency = "expired" | "warning" | "ok";

/** Raw secret metadata as provided in the (mock) configuration file. */
export interface Secret {
  /** Human-readable identifier for the secret. */
  name: string;
  /** ISO-8601 date the secret was last rotated. */
  lastRotated: string;
  /** Maximum allowed age in days before the secret must be rotated. */
  rotationPolicyDays: number;
  /** Services that depend on this secret. */
  requiredBy: string[];
}

/** A single secret enriched with its computed rotation status. */
export interface SecretStatus extends Secret {
  /** Whole days elapsed since the secret was last rotated. */
  daysSinceRotation: number;
  /** Days remaining until expiry; negative when already overdue. */
  daysUntilExpiry: number;
  /** Computed urgency bucket. */
  urgency: Urgency;
}

/** The full rotation report produced from a set of secrets. */
export interface RotationReport {
  /** ISO timestamp the report was generated for ("now"). */
  generatedAt: string;
  /** Warning window (in days) used to classify "warning" secrets. */
  warningWindowDays: number;
  /** Counts per urgency bucket plus a total. */
  summary: {
    total: number;
    expired: number;
    warning: number;
    ok: number;
  };
  /** All secret statuses, sorted most-urgent first. */
  secrets: SecretStatus[];
  /** Secret statuses grouped by urgency bucket. */
  byUrgency: {
    expired: SecretStatus[];
    warning: SecretStatus[];
    ok: SecretStatus[];
  };
}

/** Options controlling how a report is generated. */
export interface ValidateOptions {
  /** Reference "now" used for all age calculations. */
  now: Date;
  /** Days-before-expiry threshold for the "warning" bucket. */
  warningWindowDays: number;
}
