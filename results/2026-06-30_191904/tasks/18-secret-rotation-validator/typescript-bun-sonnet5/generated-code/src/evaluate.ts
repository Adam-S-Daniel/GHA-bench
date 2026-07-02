// Core rotation-status classification for a single secret.
import { daysBetween, parseIsoDate } from "./dateUtils.ts";
import type { Secret, SecretStatus, Urgency } from "./types.ts";

/**
 * Evaluates one secret's rotation status relative to `now`.
 *
 * A secret is:
 * - "expired"  when it is past its rotation policy (daysUntilExpiry < 0)
 * - "warning"  when it will expire within `warningWindowDays` (inclusive)
 * - "ok"       otherwise
 */
export function evaluateSecret(
  secret: Secret,
  now: Date,
  warningWindowDays: number,
): SecretStatus {
  const lastRotatedDate: Date = parseIsoDate(secret.lastRotated);
  const daysSinceRotation: number = daysBetween(lastRotatedDate, now);
  const daysUntilExpiry: number = secret.rotationPolicyDays - daysSinceRotation;

  let urgency: Urgency;
  if (daysUntilExpiry < 0) {
    urgency = "expired";
  } else if (daysUntilExpiry <= warningWindowDays) {
    urgency = "warning";
  } else {
    urgency = "ok";
  }

  return {
    ...secret,
    daysSinceRotation,
    daysUntilExpiry,
    urgency,
  };
}
