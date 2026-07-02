// Red/green TDD step 2: classify a single secret as expired/warning/ok.
import { describe, expect, test } from "bun:test";
import { evaluateSecret } from "../src/evaluate.ts";
import type { Secret } from "../src/types.ts";

const NOW: Date = new Date("2026-07-01T00:00:00.000Z");
const WARNING_WINDOW_DAYS: number = 14;

function makeSecret(overrides: Partial<Secret>): Secret {
  return {
    name: "test-secret",
    lastRotated: "2026-06-01",
    rotationPolicyDays: 90,
    requiredBy: ["service-a"],
    ...overrides,
  };
}

describe("evaluateSecret", () => {
  test("classifies a freshly-rotated secret as ok", () => {
    // rotated 30 days ago, policy 90 days -> 60 days of runway, well beyond the window
    const secret = makeSecret({ lastRotated: "2026-06-01", rotationPolicyDays: 90 });
    const status = evaluateSecret(secret, NOW, WARNING_WINDOW_DAYS);
    expect(status.daysSinceRotation).toBe(30);
    expect(status.daysUntilExpiry).toBe(60);
    expect(status.urgency).toBe("ok");
  });

  test("classifies a secret inside the warning window as warning", () => {
    // rotated 80 days ago, policy 90 days -> 10 days left, inside the 14-day window
    const secret = makeSecret({ lastRotated: "2026-04-12", rotationPolicyDays: 90 });
    const status = evaluateSecret(secret, NOW, WARNING_WINDOW_DAYS);
    expect(status.daysSinceRotation).toBe(80);
    expect(status.daysUntilExpiry).toBe(10);
    expect(status.urgency).toBe("warning");
  });

  test("classifies an overdue secret as expired", () => {
    // rotated 100 days ago, policy 90 days -> 10 days overdue
    const secret = makeSecret({ lastRotated: "2026-03-23", rotationPolicyDays: 90 });
    const status = evaluateSecret(secret, NOW, WARNING_WINDOW_DAYS);
    expect(status.daysSinceRotation).toBe(100);
    expect(status.daysUntilExpiry).toBe(-10);
    expect(status.urgency).toBe("expired");
  });

  test("boundary: exactly at the warning window edge is warning, not ok", () => {
    // daysUntilExpiry === warningWindowDays is still inside the window
    const secret = makeSecret({ lastRotated: "2026-04-16", rotationPolicyDays: 90 });
    const status = evaluateSecret(secret, NOW, WARNING_WINDOW_DAYS);
    expect(status.daysUntilExpiry).toBe(14);
    expect(status.urgency).toBe("warning");
  });

  test("boundary: one day past the warning window edge is ok", () => {
    const secret = makeSecret({ lastRotated: "2026-04-17", rotationPolicyDays: 90 });
    const status = evaluateSecret(secret, NOW, WARNING_WINDOW_DAYS);
    expect(status.daysUntilExpiry).toBe(15);
    expect(status.urgency).toBe("ok");
  });

  test("boundary: daysUntilExpiry exactly 0 (rotates today) is warning, not expired", () => {
    const secret = makeSecret({ lastRotated: "2026-04-02", rotationPolicyDays: 90 });
    const status = evaluateSecret(secret, NOW, WARNING_WINDOW_DAYS);
    expect(status.daysUntilExpiry).toBe(0);
    expect(status.urgency).toBe("warning");
  });

  test("boundary: one day overdue is expired", () => {
    const secret = makeSecret({ lastRotated: "2026-04-01", rotationPolicyDays: 90 });
    const status = evaluateSecret(secret, NOW, WARNING_WINDOW_DAYS);
    expect(status.daysUntilExpiry).toBe(-1);
    expect(status.urgency).toBe("expired");
  });

  test("preserves the original secret metadata on the returned status", () => {
    const secret = makeSecret({ name: "db-password", requiredBy: ["service-a", "service-b"] });
    const status = evaluateSecret(secret, NOW, WARNING_WINDOW_DAYS);
    expect(status.name).toBe("db-password");
    expect(status.requiredBy).toEqual(["service-a", "service-b"]);
    expect(status.rotationPolicyDays).toBe(90);
    expect(status.lastRotated).toBe("2026-06-01");
  });
});
