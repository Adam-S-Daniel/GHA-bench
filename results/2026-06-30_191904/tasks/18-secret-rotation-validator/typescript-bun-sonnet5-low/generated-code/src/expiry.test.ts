import { describe, test, expect } from "bun:test";
import { computeRotationStatus, classifyUrgency } from "./expiry";
import type { Secret } from "./types";

const now = new Date("2026-07-01T00:00:00Z");

describe("computeRotationStatus", () => {
  test("computes an expired secret correctly", () => {
    const secret: Secret = {
      name: "api-key-prod",
      lastRotated: "2026-01-01",
      rotationPolicyDays: 90,
      requiredBy: ["billing-service"],
    };
    const status = computeRotationStatus(secret, now);
    expect(status.expiryDate).toBe("2026-04-01");
    expect(status.daysSinceRotation).toBe(181);
    expect(status.daysUntilExpiry).toBe(-91);
    expect(status.urgency).toBe("expired");
  });

  test("computes a warning secret correctly (within warning window)", () => {
    const secret: Secret = {
      name: "oauth-token",
      lastRotated: "2026-06-15",
      rotationPolicyDays: 30,
      requiredBy: ["auth-service"],
    };
    const status = computeRotationStatus(secret, now, 14);
    expect(status.expiryDate).toBe("2026-07-15");
    expect(status.daysUntilExpiry).toBe(14);
    expect(status.urgency).toBe("warning");
  });

  test("computes an ok secret correctly (outside warning window)", () => {
    const secret: Secret = {
      name: "ssh-key",
      lastRotated: "2026-05-01",
      rotationPolicyDays: 365,
      requiredBy: ["deploy-bot"],
    };
    const status = computeRotationStatus(secret, now, 14);
    expect(status.urgency).toBe("ok");
    expect(status.daysUntilExpiry).toBeGreaterThan(14);
  });

  test("throws on invalid date", () => {
    const secret: Secret = {
      name: "bad",
      lastRotated: "not-a-date",
      rotationPolicyDays: 30,
      requiredBy: [],
    };
    expect(() => computeRotationStatus(secret, now)).toThrow(/invalid date/i);
  });

  test("throws on negative rotationPolicyDays", () => {
    const secret: Secret = {
      name: "bad",
      lastRotated: "2026-01-01",
      rotationPolicyDays: -5,
      requiredBy: [],
    };
    expect(() => computeRotationStatus(secret, now)).toThrow(/rotationPolicyDays/);
  });

  test("throws when required fields are missing", () => {
    const secret = { name: "bad" } as unknown as Secret;
    expect(() => computeRotationStatus(secret, now)).toThrow(/missing/i);
  });
});

describe("classifyUrgency", () => {
  test("classifies expired when daysUntilExpiry <= 0", () => {
    expect(classifyUrgency(-1, 14)).toBe("expired");
    expect(classifyUrgency(0, 14)).toBe("expired");
  });
  test("classifies warning when within warning window", () => {
    expect(classifyUrgency(1, 14)).toBe("warning");
    expect(classifyUrgency(14, 14)).toBe("warning");
  });
  test("classifies ok when beyond warning window", () => {
    expect(classifyUrgency(15, 14)).toBe("ok");
  });
});
