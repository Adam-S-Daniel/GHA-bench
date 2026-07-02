/** Shared domain types for the secret rotation validator. */

/** One secret entry from the configuration file (mock data). */
export interface SecretConfig {
  /** Unique, human-readable identifier of the secret. */
  name: string;
  /** ISO date (YYYY-MM-DD) the secret was last rotated. */
  lastRotated: string;
  /** Maximum age in days before the secret must be rotated again. */
  rotationPolicyDays: number;
  /** Services that consume this secret (used for notifications). */
  requiredBy: string[];
}

/** Urgency buckets, most severe first. */
export type Urgency = "expired" | "warning" | "ok";
export const URGENCIES: readonly Urgency[] = ["expired", "warning", "ok"];

/** Evaluation result for a single secret. */
export interface SecretStatus {
  secret: SecretConfig;
  urgency: Urgency;
  /** ISO date the secret expires: lastRotated + rotationPolicyDays. */
  expiresOn: string;
  /** Whole days from the reference date to expiry; negative = overdue. */
  daysUntilExpiry: number;
}

/** Full rotation report, with statuses grouped by urgency. */
export interface RotationReport {
  /** ISO reference date the report was evaluated against. */
  referenceDate: string;
  warningWindowDays: number;
  /** Count per urgency bucket. */
  summary: Record<Urgency, number>;
  /** Statuses per bucket, most urgent (smallest daysUntilExpiry) first. */
  groups: Record<Urgency, SecretStatus[]>;
}
