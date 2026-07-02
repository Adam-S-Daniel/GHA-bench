/**
 * TDD Cycle 1: core classification logic.
 *
 * A secret's expiry date is `lastRotated + rotationPolicyDays`.
 * Classification relative to a reference date ("now") and a warning window:
 *   - expired: daysUntilExpiry <= 0  (due today counts as expired — rotate now)
 *   - warning: 0 < daysUntilExpiry <= warningWindowDays
 *   - ok:      daysUntilExpiry > warningWindowDays
 *
 * All date math is done in UTC on whole days to avoid timezone drift.
 */
import { describe, expect, test } from "bun:test";
import { evaluateSecret } from "../src/validator";
import type { SecretConfig } from "../src/types";

/** Small fixture-builder so each test states only what it cares about. */
function secret(overrides: Partial<SecretConfig> = {}): SecretConfig {
  return {
    name: "db-password",
    lastRotated: "2026-01-01",
    rotationPolicyDays: 90,
    requiredBy: ["auth-service"],
    ...overrides,
  };
}

const NOW = "2026-07-02";
const WINDOW = 14;

describe("evaluateSecret", () => {
  test("classifies a long-overdue secret as expired", () => {
    // 2026-01-01 + 90 days = 2026-04-01, i.e. 92 days before NOW
    const status = evaluateSecret(secret(), NOW, WINDOW);
    expect(status.urgency).toBe("expired");
    expect(status.expiresOn).toBe("2026-04-01");
    expect(status.daysUntilExpiry).toBe(-92);
  });

  test("a secret due exactly today is expired (boundary)", () => {
    // 2026-04-10 + 83 days = 2026-07-02 = NOW
    const status = evaluateSecret(
      secret({ lastRotated: "2026-04-10", rotationPolicyDays: 83 }),
      NOW,
      WINDOW,
    );
    expect(status.urgency).toBe("expired");
    expect(status.daysUntilExpiry).toBe(0);
  });

  test("a secret expiring inside the warning window is a warning", () => {
    // 2026-05-01 + 70 days = 2026-07-10, 8 days out
    const status = evaluateSecret(
      secret({ lastRotated: "2026-05-01", rotationPolicyDays: 70 }),
      NOW,
      WINDOW,
    );
    expect(status.urgency).toBe("warning");
    expect(status.expiresOn).toBe("2026-07-10");
    expect(status.daysUntilExpiry).toBe(8);
  });

  test("a secret expiring exactly at the window edge is a warning (boundary)", () => {
    // 2026-06-16 + 30 days = 2026-07-16, exactly 14 days out
    const status = evaluateSecret(
      secret({ lastRotated: "2026-06-16", rotationPolicyDays: 30 }),
      NOW,
      WINDOW,
    );
    expect(status.urgency).toBe("warning");
    expect(status.daysUntilExpiry).toBe(14);
  });

  test("a secret expiring one day past the window is ok (boundary)", () => {
    // 2026-06-17 + 30 days = 2026-07-17, 15 days out
    const status = evaluateSecret(
      secret({ lastRotated: "2026-06-17", rotationPolicyDays: 30 }),
      NOW,
      WINDOW,
    );
    expect(status.urgency).toBe("ok");
    expect(status.daysUntilExpiry).toBe(15);
  });

  test("keeps the original secret metadata on the status", () => {
    const s = secret({ requiredBy: ["a", "b"] });
    const status = evaluateSecret(s, NOW, WINDOW);
    expect(status.secret).toEqual(s);
  });
});
