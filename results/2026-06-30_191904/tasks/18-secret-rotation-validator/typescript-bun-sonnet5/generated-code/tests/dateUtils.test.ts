// Red/green TDD step 1: date helpers used to compute secret age and expiry.
// We use whole-day UTC arithmetic so results don't depend on the host's
// local timezone (important for deterministic CI runs under act).
import { describe, expect, test } from "bun:test";
import { daysBetween, parseIsoDate } from "../src/dateUtils.ts";

describe("parseIsoDate", () => {
  test("parses a valid YYYY-MM-DD date into a UTC midnight Date", () => {
    const d = parseIsoDate("2026-06-15");
    expect(d.toISOString()).toBe("2026-06-15T00:00:00.000Z");
  });

  test("throws a descriptive error for a malformed date string", () => {
    expect(() => parseIsoDate("not-a-date")).toThrow(
      /invalid date.*not-a-date/i,
    );
  });

  test("throws a descriptive error for an out-of-range calendar date", () => {
    expect(() => parseIsoDate("2026-02-30")).toThrow(
      /invalid date.*2026-02-30/i,
    );
  });
});

describe("daysBetween", () => {
  test("computes whole days between two UTC dates", () => {
    const from = parseIsoDate("2026-06-01");
    const to = parseIsoDate("2026-07-01");
    expect(daysBetween(from, to)).toBe(30);
  });

  test("returns 0 for the same day", () => {
    const d = parseIsoDate("2026-07-01");
    expect(daysBetween(d, d)).toBe(0);
  });

  test("returns a negative number when `to` is before `from`", () => {
    const from = parseIsoDate("2026-07-01");
    const to = parseIsoDate("2026-06-01");
    expect(daysBetween(from, to)).toBe(-30);
  });
});
