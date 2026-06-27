// TDD: red/green tests for the core secret-rotation classification logic.
// We start here — defining the contract for classifying a single secret by
// urgency relative to a fixed "now" and a configurable warning window.
import { describe, expect, test } from "bun:test";
import { classifySecret, validateSecrets } from "../src/validator";
import type { Secret } from "../src/types";

// A fixed reference date keeps every assertion deterministic regardless of
// when the suite actually runs (critical for CI exact-value checks).
const NOW = new Date("2026-06-27T00:00:00.000Z");

function makeSecret(overrides: Partial<Secret> = {}): Secret {
  return {
    name: "db-password",
    lastRotated: "2026-06-01T00:00:00.000Z",
    rotationPolicyDays: 90,
    requiredBy: ["api"],
    ...overrides,
  };
}

describe("classifySecret", () => {
  test("computes days since rotation and days until expiry", () => {
    // Rotated 26 days ago, policy 90 days -> 64 days until expiry.
    const status = classifySecret(makeSecret(), NOW, 14);
    expect(status.daysSinceRotation).toBe(26);
    expect(status.daysUntilExpiry).toBe(64);
    expect(status.urgency).toBe("ok");
  });

  test("flags a secret past its policy as expired", () => {
    // Rotated 100 days ago with a 90-day policy -> 10 days overdue.
    const status = classifySecret(
      makeSecret({ lastRotated: "2026-03-19T00:00:00.000Z" }),
      NOW,
      14,
    );
    expect(status.daysUntilExpiry).toBe(-10);
    expect(status.urgency).toBe("expired");
  });

  test("flags a secret inside the warning window", () => {
    // Rotated 80 days ago, policy 90 -> 10 days left, within a 14-day window.
    const status = classifySecret(
      makeSecret({ lastRotated: "2026-04-08T00:00:00.000Z" }),
      NOW,
      14,
    );
    expect(status.daysUntilExpiry).toBe(10);
    expect(status.urgency).toBe("warning");
  });

  test("treats a secret due exactly today as expired", () => {
    const status = classifySecret(
      makeSecret({ lastRotated: "2026-03-29T00:00:00.000Z" }),
      NOW,
      14,
    );
    expect(status.daysUntilExpiry).toBe(0);
    expect(status.urgency).toBe("expired");
  });

  test("respects a configurable warning window", () => {
    const secret = makeSecret({ lastRotated: "2026-04-08T00:00:00.000Z" }); // 10 days left
    expect(classifySecret(secret, NOW, 5).urgency).toBe("ok");
    expect(classifySecret(secret, NOW, 10).urgency).toBe("warning");
  });
});

describe("validateSecrets", () => {
  test("builds a report grouped by urgency with a summary", () => {
    const secrets: Secret[] = [
      makeSecret({ name: "ok-secret", lastRotated: "2026-06-01T00:00:00.000Z" }),
      makeSecret({ name: "warn-secret", lastRotated: "2026-04-08T00:00:00.000Z" }),
      makeSecret({ name: "expired-secret", lastRotated: "2026-01-01T00:00:00.000Z" }),
    ];
    const report = validateSecrets(secrets, { now: NOW, warningWindowDays: 14 });

    expect(report.summary).toEqual({ total: 3, expired: 1, warning: 1, ok: 1 });
    expect(report.byUrgency.expired.map((s) => s.name)).toEqual(["expired-secret"]);
    expect(report.byUrgency.warning.map((s) => s.name)).toEqual(["warn-secret"]);
    expect(report.byUrgency.ok.map((s) => s.name)).toEqual(["ok-secret"]);
    expect(report.warningWindowDays).toBe(14);
  });

  test("sorts secrets by urgency then by days until expiry", () => {
    const secrets: Secret[] = [
      makeSecret({ name: "ok", lastRotated: "2026-06-20T00:00:00.000Z" }),
      makeSecret({ name: "very-expired", lastRotated: "2025-01-01T00:00:00.000Z" }),
      makeSecret({ name: "slightly-expired", lastRotated: "2026-03-01T00:00:00.000Z" }),
    ];
    const report = validateSecrets(secrets, { now: NOW, warningWindowDays: 14 });
    // Most urgent (most overdue) first.
    expect(report.secrets.map((s) => s.name)).toEqual([
      "very-expired",
      "slightly-expired",
      "ok",
    ]);
  });
});
