// Whole-day UTC date arithmetic, kept isolated so rotation-status logic
// never has to worry about local-timezone drift.

const ISO_DATE_PATTERN: RegExp = /^\d{4}-\d{2}-\d{2}$/;
const MS_PER_DAY: number = 24 * 60 * 60 * 1000;

/**
 * Parses a "YYYY-MM-DD" string into a Date at UTC midnight.
 * Throws a descriptive error for malformed strings or invalid calendar
 * dates (e.g. "2026-02-30", which JS would otherwise silently roll over
 * into March).
 */
export function parseIsoDate(value: string): Date {
  if (!ISO_DATE_PATTERN.test(value)) {
    throw new Error(`Invalid date "${value}": expected format YYYY-MM-DD`);
  }

  const [yearStr, monthStr, dayStr] = value.split("-") as [
    string,
    string,
    string,
  ];
  const year: number = Number(yearStr);
  const month: number = Number(monthStr);
  const day: number = Number(dayStr);

  const date: Date = new Date(Date.UTC(year, month - 1, day));
  const rolledOver: boolean =
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day;

  if (rolledOver) {
    throw new Error(`Invalid date "${value}": not a real calendar date`);
  }

  return date;
}

/** Returns the whole number of days from `from` to `to` (can be negative). */
export function daysBetween(from: Date, to: Date): number {
  return Math.round((to.getTime() - from.getTime()) / MS_PER_DAY);
}
