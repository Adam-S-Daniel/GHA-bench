// Shared type definitions for the secret rotation validator.

/** A single secret's rotation metadata (all mock data — no real credentials involved). */
export interface SecretMeta {
  name: string;
  /** ISO 8601 date string (YYYY-MM-DD) of the last rotation. */
  lastRotated: string;
  /** How often the secret must be rotated, in days. */
  rotationPolicyDays: number;
  /** Services that depend on this secret. */
  requiredBy: string[];
}

/** Top-level configuration file shape. */
export interface RotationConfig {
  /** Days before expiry at which a secret enters the "warning" bucket. */
  warningWindowDays: number;
  secrets: SecretMeta[];
}

/** Urgency bucket a secret falls into relative to the reference date. */
export type Urgency = "expired" | "warning" | "ok";

/** Computed rotation status for a single secret. */
export interface SecretStatus {
  name: string;
  requiredBy: string[];
  lastRotated: string;
  rotationPolicyDays: number;
  /** Days since the secret was last rotated (as of the reference date). */
  daysSinceRotation: number;
  /** Days remaining until the secret expires. Negative means already expired. */
  daysUntilExpiry: number;
  urgency: Urgency;
}

/** Full rotation report, secrets grouped by urgency. */
export interface RotationReport {
  generatedAt: string;
  warningWindowDays: number;
  expired: SecretStatus[];
  warning: SecretStatus[];
  ok: SecretStatus[];
}

export type OutputFormat = "markdown" | "json";
