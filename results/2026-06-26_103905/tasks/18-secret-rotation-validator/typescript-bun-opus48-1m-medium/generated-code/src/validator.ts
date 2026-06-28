// Core domain model + classification logic for the secret rotation validator.
// Kept free of any I/O so it is trivially unit-testable.

/** A single secret and its rotation metadata (mock data in fixtures). */
export interface Secret {
  /** Unique, human-readable identifier, e.g. "DB_PASSWORD". */
  name: string;
  /** ISO-8601 date (YYYY-MM-DD) the secret was last rotated. */
  lastRotated: string;
  /** Maximum allowed age, in days, before rotation is due. */
  rotationPolicyDays: number;
  /** Services that depend on this secret (used for blast-radius reporting). */
  requiredBy: string[];
}

/** Top-level configuration: a collection of secrets to validate. */
export interface SecretConfig {
  secrets: Secret[];
}

/** Urgency buckets, most to least severe. */
export type Status = "expired" | "warning" | "ok";

/** Options controlling classification. `now` is injected for deterministic tests. */
export interface ClassifyOptions {
  /** The reference "current" date. */
  now: Date;
  /** How many days ahead of the due date we begin warning. */
  warningWindowDays: number;
}

/** Result of evaluating a single secret. */
export interface SecretEvaluation {
  secret: Secret;
  status: Status;
  /** Days until rotation is due. Negative means overdue (expired). */
  daysUntilDue: number;
  /** Convenience flag equivalent to `status === "expired"`. */
  expired: boolean;
  /** The date rotation is/was due. */
  dueDate: Date;
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Parse an ISO date string into a UTC Date, throwing a meaningful error on bad input. */
export function parseIsoDate(value: string, context: string): Date {
  // Enforce a strict YYYY-MM-DD shape so silent NaN dates can't slip through.
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`Invalid date "${value}" for ${context}: expected YYYY-MM-DD format`);
  }
  const date = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Invalid date "${value}" for ${context}: not a real calendar date`);
  }
  return date;
}

/** Whole-day difference (b - a), truncated toward zero. */
function diffInDays(a: Date, b: Date): number {
  return Math.trunc((b.getTime() - a.getTime()) / MS_PER_DAY);
}

/**
 * Classify a single secret into an urgency bucket.
 *
 * Rules:
 *   dueDate       = lastRotated + rotationPolicyDays
 *   daysUntilDue  = dueDate - now
 *   expired       when daysUntilDue < 0
 *   warning       when 0 <= daysUntilDue <= warningWindowDays
 *   ok            otherwise
 */
export function classifySecret(secret: Secret, options: ClassifyOptions): SecretEvaluation {
  if (secret.rotationPolicyDays <= 0) {
    throw new Error(
      `Secret "${secret.name}" has an invalid rotationPolicyDays (${secret.rotationPolicyDays}): must be a positive number`,
    );
  }
  if (options.warningWindowDays < 0) {
    throw new Error(`warningWindowDays must be >= 0, got ${options.warningWindowDays}`);
  }

  const lastRotated = parseIsoDate(secret.lastRotated, `secret "${secret.name}"`);
  const dueDate = new Date(lastRotated.getTime() + secret.rotationPolicyDays * MS_PER_DAY);
  const daysUntilDue = diffInDays(options.now, dueDate);

  let status: Status;
  if (daysUntilDue < 0) {
    status = "expired";
  } else if (daysUntilDue <= options.warningWindowDays) {
    status = "warning";
  } else {
    status = "ok";
  }

  return {
    secret,
    status,
    daysUntilDue,
    expired: status === "expired",
    dueDate,
  };
}
