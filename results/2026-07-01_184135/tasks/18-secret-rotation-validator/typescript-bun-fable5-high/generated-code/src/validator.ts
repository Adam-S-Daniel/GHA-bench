/**
 * Core validation logic: date math and urgency classification.
 *
 * Approach: all dates are plain ISO days (YYYY-MM-DD) handled in UTC
 * milliseconds, so results are identical regardless of the host timezone.
 */
import type { SecretConfig, SecretStatus } from "./types";

const MS_PER_DAY = 86_400_000;

/** Parse a strict YYYY-MM-DD date into UTC ms. Throws on anything else. */
export function parseIsoDate(value: string): number {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) {
    throw new Error(`invalid date "${value}" (expected YYYY-MM-DD)`);
  }
  const [, y, m, d] = match;
  const ms = Date.UTC(Number(y), Number(m) - 1, Number(d));
  // Reject calendar-impossible dates like 2026-02-30, which Date.UTC rolls over.
  const roundTrip = new Date(ms).toISOString().slice(0, 10);
  if (roundTrip !== value) {
    throw new Error(`invalid date "${value}" (not a real calendar day)`);
  }
  return ms;
}

/** Format UTC ms back to YYYY-MM-DD. */
function toIsoDate(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/**
 * Classify one secret against a reference date and warning window.
 *   expired: due today or overdue (daysUntilExpiry <= 0)
 *   warning: expires within the window (0 < days <= window)
 *   ok:      expires after the window
 */
export function evaluateSecret(
  secret: SecretConfig,
  referenceDate: string,
  warningWindowDays: number,
): SecretStatus {
  const nowMs = parseIsoDate(referenceDate);
  const expiresMs =
    parseIsoDate(secret.lastRotated) + secret.rotationPolicyDays * MS_PER_DAY;
  const daysUntilExpiry = Math.round((expiresMs - nowMs) / MS_PER_DAY);

  const urgency =
    daysUntilExpiry <= 0
      ? "expired"
      : daysUntilExpiry <= warningWindowDays
        ? "warning"
        : "ok";

  return { secret, urgency, expiresOn: toIsoDate(expiresMs), daysUntilExpiry };
}
