/**
 * Core validation logic: classify secrets against their rotation policy.
 *
 * All date math is done in UTC on whole days so results are deterministic
 * regardless of the machine's timezone. "now" is always injected by the
 * caller (never read from the system clock inside this module) so that both
 * tests and CI runs produce reproducible output.
 */
import type { RotationReport, Secret, SecretStatus, Urgency } from "./types";

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Parse an ISO date string to a UTC midnight timestamp, or null if invalid. */
function parseIsoDate(value: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const ms = Date.parse(`${value}T00:00:00Z`);
  return Number.isNaN(ms) ? null : ms;
}

/** Truncate any timestamp to UTC midnight of the same day. */
function utcMidnight(date: Date): number {
  return Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate(),
  );
}

/** Format a UTC timestamp back to YYYY-MM-DD. */
function toIsoDate(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/**
 * Classify a single secret.
 *
 * - "expired": due today or overdue (daysUntilExpiry <= 0)
 * - "warning": expires within `warningWindowDays` (inclusive)
 * - "ok":      everything else
 */
export function classifySecret(
  secret: Secret,
  now: Date,
  warningWindowDays: number,
): SecretStatus {
  const rotatedMs = parseIsoDate(secret.lastRotated);
  if (rotatedMs === null) {
    throw new Error(
      `Secret "${secret.name}" has an invalid lastRotated date: "${secret.lastRotated}" (expected YYYY-MM-DD)`,
    );
  }
  if (
    !Number.isInteger(secret.rotationPolicyDays) ||
    secret.rotationPolicyDays <= 0
  ) {
    throw new Error(
      `Secret "${secret.name}" has an invalid rotationPolicyDays: ${secret.rotationPolicyDays} (must be a positive integer)`,
    );
  }

  const expiryMs = rotatedMs + secret.rotationPolicyDays * MS_PER_DAY;
  const daysUntilExpiry = Math.round((expiryMs - utcMidnight(now)) / MS_PER_DAY);

  let status: Urgency;
  if (daysUntilExpiry <= 0) {
    status = "expired";
  } else if (daysUntilExpiry <= warningWindowDays) {
    status = "warning";
  } else {
    status = "ok";
  }

  return { secret, status, expiresOn: toIsoDate(expiryMs), daysUntilExpiry };
}

/**
 * Classify every secret and group the results by urgency.
 * Each bucket is sorted most-urgent-first (fewest days until expiry) so the
 * rendered report reads top-down in priority order.
 */
export function buildReport(
  secrets: Secret[],
  now: Date,
  warningWindowDays: number,
): RotationReport {
  if (!Number.isInteger(warningWindowDays) || warningWindowDays < 0) {
    throw new Error(
      `warningWindowDays must be a non-negative integer, got: ${warningWindowDays}`,
    );
  }

  const seen = new Set<string>();
  for (const secret of secrets) {
    if (seen.has(secret.name)) {
      throw new Error(`Duplicate secret name in configuration: "${secret.name}"`);
    }
    seen.add(secret.name);
  }

  const buckets: Record<Urgency, SecretStatus[]> = {
    expired: [],
    warning: [],
    ok: [],
  };
  for (const secret of secrets) {
    const result = classifySecret(secret, now, warningWindowDays);
    buckets[result.status].push(result);
  }
  for (const bucket of Object.values(buckets)) {
    bucket.sort((a, b) => a.daysUntilExpiry - b.daysUntilExpiry);
  }

  return {
    generatedFor: toIsoDate(utcMidnight(now)),
    warningWindowDays,
    ...buckets,
  };
}
