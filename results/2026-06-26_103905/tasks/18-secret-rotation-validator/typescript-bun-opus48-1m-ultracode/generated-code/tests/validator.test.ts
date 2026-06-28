/**
 * Cycle 1 (red/green TDD): core date math + per-secret evaluation.
 *
 * These unit tests pin down the pure logic before any CLI / workflow plumbing
 * exists. They are intentionally deterministic — every test fixes a reference
 * "now" date so results never depend on the wall clock.
 */
import { describe, expect, test } from "bun:test";
import {
  parseDate,
  formatDate,
  daysBetween,
  addDays,
  classify,
  evaluateSecret,
} from "../src/validator";
import type { SecretConfig } from "../src/types";

// Fixed reference date shared across the suite for reproducibility.
const NOW = parseDate("2026-06-28");

describe("date helpers", () => {
  test("parseDate accepts strict YYYY-MM-DD as UTC midnight", () => {
    const d = parseDate("2026-01-01");
    expect(d.getUTCFullYear()).toBe(2026);
    expect(d.getUTCMonth()).toBe(0); // January is month 0
    expect(d.getUTCDate()).toBe(1);
  });

  test("parseDate rejects malformed or impossible dates with a clear error", () => {
    expect(() => parseDate("2026/01/01")).toThrow(/Invalid date/);
    expect(() => parseDate("2026-13-01")).toThrow(/Invalid date/);
    expect(() => parseDate("2026-02-30")).toThrow(/Invalid date/); // 2026 is not a leap year
    expect(() => parseDate("not-a-date")).toThrow(/Invalid date/);
    expect(() => parseDate("")).toThrow(/Invalid date/);
  });

  test("daysBetween returns whole, signed UTC day differences", () => {
    expect(daysBetween(parseDate("2026-01-11"), parseDate("2026-01-01"))).toBe(10);
    expect(daysBetween(parseDate("2026-01-01"), parseDate("2026-01-11"))).toBe(-10);
    expect(daysBetween(parseDate("2026-01-01"), parseDate("2026-01-01"))).toBe(0);
  });

  test("addDays advances by calendar days and formatDate round-trips", () => {
    expect(formatDate(addDays(parseDate("2026-01-01"), 90))).toBe("2026-04-01");
    expect(formatDate(addDays(parseDate("2026-05-01"), 60))).toBe("2026-06-30");
  });
});

describe("classify", () => {
  test("negative days-until-expiry is expired", () => {
    expect(classify(-1, 14)).toBe("expired");
    expect(classify(-88, 14)).toBe("expired");
  });

  test("within the warning window (inclusive on both ends) is warning", () => {
    expect(classify(0, 14)).toBe("warning"); // expires today
    expect(classify(14, 14)).toBe("warning"); // last day of the window
  });

  test("beyond the warning window is ok", () => {
    expect(classify(15, 14)).toBe("ok");
    expect(classify(63, 14)).toBe("ok");
  });
});

describe("evaluateSecret", () => {
  const expiredSecret: SecretConfig = {
    name: "AWS_ACCESS_KEY",
    lastRotated: "2026-01-01",
    rotationPolicyDays: 90,
    requiredBy: ["api", "worker"],
  };

  test("computes expiry, ages, and urgency for an overdue secret", () => {
    const s = evaluateSecret(expiredSecret, NOW, 14);
    expect(s.expiryDate).toBe("2026-04-01");
    expect(s.daysSinceRotation).toBe(178);
    expect(s.daysUntilExpiry).toBe(-88);
    expect(s.urgency).toBe("expired");
    // Metadata is carried through untouched.
    expect(s.requiredBy).toEqual(["api", "worker"]);
    expect(s.name).toBe("AWS_ACCESS_KEY");
  });

  test("classifies a soon-to-expire secret as warning", () => {
    const s = evaluateSecret(
      { name: "DB_PASSWORD", lastRotated: "2026-05-01", rotationPolicyDays: 60, requiredBy: ["api"] },
      NOW,
      14,
    );
    expect(s.expiryDate).toBe("2026-06-30");
    expect(s.daysUntilExpiry).toBe(2);
    expect(s.urgency).toBe("warning");
  });

  test("classifies a freshly-rotated secret as ok", () => {
    const s = evaluateSecret(
      { name: "STRIPE_API_KEY", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["billing"] },
      NOW,
      14,
    );
    expect(s.urgency).toBe("ok");
    expect(s.daysUntilExpiry).toBe(63);
  });

  test("a wider warning window can pull a secret from ok into warning", () => {
    const cfg: SecretConfig = {
      name: "JWT_SIGNING_KEY",
      lastRotated: "2026-06-20",
      rotationPolicyDays: 30,
      requiredBy: ["auth"],
    };
    expect(evaluateSecret(cfg, NOW, 14).urgency).toBe("ok"); // 22 days out
    expect(evaluateSecret(cfg, NOW, 30).urgency).toBe("warning");
  });
});
