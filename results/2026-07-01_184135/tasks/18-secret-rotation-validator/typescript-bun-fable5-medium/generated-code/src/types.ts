/**
 * Shared domain types for the secret rotation validator.
 */

/** A secret as declared in the configuration file (mock data). */
export interface Secret {
  /** Unique human-readable identifier, e.g. "db-password". */
  name: string;
  /** ISO 8601 date (YYYY-MM-DD) of the last rotation. */
  lastRotated: string;
  /** How often the secret must be rotated, in days. Must be a positive integer. */
  rotationPolicyDays: number;
  /** Services that depend on this secret. */
  requiredBy: string[];
}

/** Urgency buckets, ordered from most to least urgent. */
export type Urgency = "expired" | "warning" | "ok";

/** The result of evaluating one secret against the rotation policy. */
export interface SecretStatus {
  secret: Secret;
  status: Urgency;
  /** ISO date (YYYY-MM-DD) on which the secret expires. */
  expiresOn: string;
  /** Whole days until expiry; zero or negative means expired. */
  daysUntilExpiry: number;
}

/** A full rotation report: every secret grouped by urgency. */
export interface RotationReport {
  /** ISO date the report was generated for (the injected "now"). */
  generatedFor: string;
  warningWindowDays: number;
  expired: SecretStatus[];
  warning: SecretStatus[];
  ok: SecretStatus[];
}
