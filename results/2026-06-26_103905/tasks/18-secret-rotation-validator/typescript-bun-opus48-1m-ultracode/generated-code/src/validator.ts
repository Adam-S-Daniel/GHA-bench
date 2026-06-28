/**
 * Core, side-effect-free logic for the secret rotation validator.
 *
 * Everything here is pure: given the same inputs it always produces the same
 * output. All date math is done in UTC so results never depend on the machine
 * timezone or on daylight-saving transitions — important because the same
 * fixtures must produce identical results on a developer laptop and inside the
 * GitHub Actions / `act` container.
 */
import type {
  SecretConfig,
  SecretStatus,
  Urgency,
  UrgencyGroups,
  RotationReport,
} from "./types";

/** Milliseconds in a day. UTC days are always exactly this long. */
const MS_PER_DAY = 86_400_000;

/** Strict `YYYY-MM-DD` shape check before we attempt to build a Date. */
const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

/**
 * Parse a strict `YYYY-MM-DD` calendar date into a UTC-midnight `Date`.
 *
 * We deliberately do NOT use `new Date(string)` directly: it is lenient and
 * timezone-sensitive (it would happily accept "2026-02-30" by rolling over to
 * March). Instead we validate the shape, build the date in UTC, and confirm the
 * components round-trip — rejecting impossible dates like Feb 30.
 */
export function parseDate(input: string): Date {
  const match = DATE_RE.exec(input);
  if (!match) {
    throw new Error(`Invalid date "${input}": expected strict YYYY-MM-DD format.`);
  }
  const year = Number(match[1]);
  const month = Number(match[2]); // 1-12
  const day = Number(match[3]); // 1-31
  const date = new Date(Date.UTC(year, month - 1, day));
  // Reject overflow (e.g. 2026-02-30 -> 2026-03-02) by checking round-trip.
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new Error(`Invalid date "${input}": not a real calendar date.`);
  }
  return date;
}

/** Format a `Date` back into a `YYYY-MM-DD` string using its UTC components. */
export function formatDate(date: Date): string {
  const y = date.getUTCFullYear().toString().padStart(4, "0");
  const m = (date.getUTCMonth() + 1).toString().padStart(2, "0");
  const d = date.getUTCDate().toString().padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/** Whole, signed day difference `a - b` (positive when `a` is later than `b`). */
export function daysBetween(a: Date, b: Date): number {
  return Math.round((a.getTime() - b.getTime()) / MS_PER_DAY);
}

/** Return a new `Date` advanced by `days` calendar days (UTC-safe). */
export function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * MS_PER_DAY);
}

/**
 * Bucket a secret by how many days remain until it expires.
 *
 * - `daysUntilExpiry < 0`            -> expired (already overdue)
 * - `0 <= daysUntilExpiry <= window` -> warning (due now or within the window)
 * - `daysUntilExpiry > window`       -> ok
 */
export function classify(daysUntilExpiry: number, warningWindowDays: number): Urgency {
  if (daysUntilExpiry < 0) return "expired";
  if (daysUntilExpiry <= warningWindowDays) return "warning";
  return "ok";
}

/**
 * Evaluate a single secret against a reference `now` date and warning window.
 * Returns the original config enriched with computed expiry/age/urgency fields.
 */
export function evaluateSecret(
  config: SecretConfig,
  now: Date,
  warningWindowDays: number,
): SecretStatus {
  const lastRotated = parseDate(config.lastRotated);
  const expiry = addDays(lastRotated, config.rotationPolicyDays);
  const daysSinceRotation = daysBetween(now, lastRotated);
  const daysUntilExpiry = daysBetween(expiry, now);
  return {
    ...config,
    expiryDate: formatDate(expiry),
    daysSinceRotation,
    daysUntilExpiry,
    urgency: classify(daysUntilExpiry, warningWindowDays),
  };
}

/**
 * Build the full rotation report for a list of secrets.
 *
 * Secrets are evaluated, grouped by urgency, and each group is sorted by
 * `daysUntilExpiry` ascending (the most overdue / soonest-to-expire first) so
 * the report surfaces the scariest items at the top of every section.
 */
export function buildReport(
  configs: SecretConfig[],
  now: Date,
  warningWindowDays: number,
): RotationReport {
  const evaluated = configs.map((c) => evaluateSecret(c, now, warningWindowDays));

  const groups: UrgencyGroups = { expired: [], warning: [], ok: [] };
  for (const status of evaluated) {
    groups[status.urgency].push(status);
  }

  const byExpiry = (a: SecretStatus, b: SecretStatus): number =>
    a.daysUntilExpiry - b.daysUntilExpiry || a.name.localeCompare(b.name);
  groups.expired.sort(byExpiry);
  groups.warning.sort(byExpiry);
  groups.ok.sort(byExpiry);

  return {
    generatedAt: formatDate(now),
    warningWindowDays,
    summary: {
      total: evaluated.length,
      expired: groups.expired.length,
      warning: groups.warning.length,
      ok: groups.ok.length,
    },
    groups,
  };
}
