// Core classification logic for the secret-rotation validator.
// Kept pure and free of I/O so it is trivially unit-testable.
import type {
  RotationReport,
  Secret,
  SecretStatus,
  Urgency,
  ValidateOptions,
} from "./types";

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Numeric ordering used to sort urgency buckets (lower = more urgent). */
const URGENCY_RANK: Record<Urgency, number> = {
  expired: 0,
  warning: 1,
  ok: 2,
};

/**
 * Classify a single secret relative to a reference date and warning window.
 *
 * - `daysSinceRotation` = whole days between `lastRotated` and `now`.
 * - `daysUntilExpiry`   = policy length minus the age (negative when overdue).
 * - A secret due today or overdue (`<= 0`) is `expired`; one within the
 *   warning window is `warning`; anything else is `ok`.
 *
 * @throws if the secret's metadata is invalid.
 */
export function classifySecret(
  secret: Secret,
  now: Date,
  warningWindowDays: number,
): SecretStatus {
  const rotated = new Date(secret.lastRotated);
  if (Number.isNaN(rotated.getTime())) {
    throw new Error(
      `Secret "${secret.name}" has an invalid lastRotated date: "${secret.lastRotated}"`,
    );
  }
  if (
    typeof secret.rotationPolicyDays !== "number" ||
    !Number.isFinite(secret.rotationPolicyDays) ||
    secret.rotationPolicyDays <= 0
  ) {
    throw new Error(
      `Secret "${secret.name}" has an invalid rotationPolicyDays: ${secret.rotationPolicyDays}`,
    );
  }

  // Floor to whole days so partial days never tip a secret into "expired".
  const daysSinceRotation = Math.floor(
    (now.getTime() - rotated.getTime()) / MS_PER_DAY,
  );
  const daysUntilExpiry = secret.rotationPolicyDays - daysSinceRotation;

  let urgency: Urgency;
  if (daysUntilExpiry <= 0) {
    urgency = "expired";
  } else if (daysUntilExpiry <= warningWindowDays) {
    urgency = "warning";
  } else {
    urgency = "ok";
  }

  return { ...secret, daysSinceRotation, daysUntilExpiry, urgency };
}

/**
 * Validate a collection of secrets, producing a full rotation report:
 * statuses sorted most-urgent-first, grouped by urgency, plus a summary.
 */
export function validateSecrets(
  secrets: Secret[],
  options: ValidateOptions,
): RotationReport {
  const { now, warningWindowDays } = options;
  if (warningWindowDays < 0) {
    throw new Error(
      `warningWindowDays must be non-negative, got ${warningWindowDays}`,
    );
  }

  const statuses = secrets.map((s) =>
    classifySecret(s, now, warningWindowDays),
  );

  // Sort by urgency bucket, then by soonest expiry (most overdue first),
  // then alphabetically by name for a stable, predictable ordering.
  statuses.sort((a, b) => {
    if (URGENCY_RANK[a.urgency] !== URGENCY_RANK[b.urgency]) {
      return URGENCY_RANK[a.urgency] - URGENCY_RANK[b.urgency];
    }
    if (a.daysUntilExpiry !== b.daysUntilExpiry) {
      return a.daysUntilExpiry - b.daysUntilExpiry;
    }
    return a.name.localeCompare(b.name);
  });

  const byUrgency = {
    expired: statuses.filter((s) => s.urgency === "expired"),
    warning: statuses.filter((s) => s.urgency === "warning"),
    ok: statuses.filter((s) => s.urgency === "ok"),
  };

  return {
    generatedAt: now.toISOString(),
    warningWindowDays,
    summary: {
      total: statuses.length,
      expired: byUrgency.expired.length,
      warning: byUrgency.warning.length,
      ok: byUrgency.ok.length,
    },
    secrets: statuses,
    byUrgency,
  };
}
