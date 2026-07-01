// Shared domain types for the secret rotation validator.

/** Urgency bucket a secret is grouped into for notifications. */
export type Urgency = "expired" | "warning" | "ok";

/** A single secret's metadata, as read from the config file (mock data). */
export interface Secret {
  name: string;
  /** Date the secret was last rotated, formatted "YYYY-MM-DD". */
  lastRotated: string;
  /** How often the secret must be rotated, in days. */
  rotationPolicyDays: number;
  /** Services that depend on this secret. */
  requiredBy: string[];
}

/** Top-level shape of a secrets configuration file. */
export interface SecretsConfig {
  secrets: Secret[];
  /** Days before expiry a secret is flagged "warning". Defaults if omitted. */
  warningWindowDays?: number;
}

/** A secret enriched with computed rotation-status fields. */
export interface SecretStatus extends Secret {
  /** Whole days since the secret was last rotated (relative to `now`). */
  daysSinceRotation: number;
  /**
   * Days remaining before the rotation policy is violated.
   * Negative means the secret is already overdue by that many days.
   */
  daysUntilExpiry: number;
  urgency: Urgency;
}

/** Full rotation report: every secret's status, grouped by urgency. */
export interface RotationReport {
  generatedAt: string;
  warningWindowDays: number;
  totalSecrets: number;
  expired: SecretStatus[];
  warning: SecretStatus[];
  ok: SecretStatus[];
}

export type OutputFormat = "markdown" | "json";
