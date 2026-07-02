// RED/GREEN cycle 1: classification of a single secret.
//
// Rules under test (the core domain logic):
//   expiryDate      = lastRotated + rotationPolicyDays
//   daysUntilExpiry = whole days from `now` to expiryDate
//   status:
//     - "expired" when daysUntilExpiry <= 0 (due today counts as expired)
//     - "warning" when 0 < daysUntilExpiry <= warningWindowDays
//     - "ok"      otherwise
//
// `now` is always injected so tests and CI runs are deterministic.
import { describe, expect, test } from "bun:test";
import { classifySecret } from "../src/validator";
import type { Secret } from "../src/types";

const NOW = new Date("2026-07-01T00:00:00Z");

function secret(overrides: Partial<Secret> = {}): Secret {
  return {
    name: "db-password",
    lastRotated: "2026-06-01",
    rotationPolicyDays: 90,
    requiredBy: ["api", "worker"],
    ...overrides,
  };
}

describe("classifySecret", () => {
  test("secret well within its rotation policy is ok", () => {
    // Rotated 2026-06-01 with a 90-day policy -> expires 2026-08-30 (60 days out)
    const result = classifySecret(secret(), NOW, 14);
    expect(result.status).toBe("ok");
    expect(result.daysUntilExpiry).toBe(60);
    expect(result.expiresOn).toBe("2026-08-30");
  });

  test("secret past its expiry date is expired", () => {
    // Rotated 2026-03-01 with a 90-day policy -> expired 2026-05-30 (32 days ago)
    const result = classifySecret(
      secret({ lastRotated: "2026-03-01" }),
      NOW,
      14,
    );
    expect(result.status).toBe("expired");
    expect(result.daysUntilExpiry).toBe(-32);
  });

  test("secret expiring today is treated as expired", () => {
    // Rotated 2026-04-02 + 90 days -> expires exactly on NOW (2026-07-01)
    const result = classifySecret(
      secret({ lastRotated: "2026-04-02" }),
      NOW,
      14,
    );
    expect(result.status).toBe("expired");
    expect(result.daysUntilExpiry).toBe(0);
  });

  test("secret inside the warning window is warning", () => {
    // Rotated 2026-04-09 + 90 days -> expires 2026-07-08, 7 days out, window 14
    const result = classifySecret(
      secret({ lastRotated: "2026-04-09" }),
      NOW,
      14,
    );
    expect(result.status).toBe("warning");
    expect(result.daysUntilExpiry).toBe(7);
  });

  test("secret exactly at the edge of the warning window is warning", () => {
    // Expires in exactly 14 days with a 14-day window -> still a warning
    const result = classifySecret(
      secret({ lastRotated: "2026-04-16" }),
      NOW,
      14,
    );
    expect(result.status).toBe("warning");
    expect(result.daysUntilExpiry).toBe(14);
  });

  test("rejects an invalid lastRotated date with a clear message", () => {
    expect(() =>
      classifySecret(secret({ lastRotated: "not-a-date" }), NOW, 14),
    ).toThrow('Secret "db-password" has an invalid lastRotated date: "not-a-date"');
  });

  test("rejects a non-positive rotation policy", () => {
    expect(() =>
      classifySecret(secret({ rotationPolicyDays: 0 }), NOW, 14),
    ).toThrow('Secret "db-password" has an invalid rotationPolicyDays: 0 (must be a positive integer)');
  });
});
