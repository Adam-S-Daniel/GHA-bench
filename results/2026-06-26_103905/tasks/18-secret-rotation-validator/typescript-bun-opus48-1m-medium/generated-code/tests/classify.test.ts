// RED step #1: drive out the core classification logic.
// A secret's urgency is a pure function of:
//   - when it was last rotated
//   - its rotation policy (max age in days)
//   - the warning window (how many days ahead we start warning)
//   - the reference "now" date (injected for deterministic tests)
import { describe, expect, it } from "bun:test";
import { classifySecret, type Secret } from "../src/validator.ts";

// A fixed reference date keeps every test deterministic regardless of the wall clock.
const NOW = new Date("2026-06-27T00:00:00Z");

function makeSecret(overrides: Partial<Secret> = {}): Secret {
  return {
    name: "DB_PASSWORD",
    lastRotated: "2026-01-01",
    rotationPolicyDays: 90,
    requiredBy: ["api"],
    ...overrides,
  };
}

describe("classifySecret", () => {
  it("marks a secret OK when it is well within its rotation policy", () => {
    // Rotated today, 90-day policy: tons of headroom.
    const secret = makeSecret({ lastRotated: "2026-06-27", rotationPolicyDays: 90 });
    const result = classifySecret(secret, { now: NOW, warningWindowDays: 14 });

    expect(result.status).toBe("ok");
    expect(result.daysUntilDue).toBe(90);
    expect(result.expired).toBe(false);
  });

  it("marks a secret WARNING when due within the warning window", () => {
    // 2026-04-08 + 90 days = 2026-07-07, which is 10 days after NOW (2026-06-27).
    const secret = makeSecret({ lastRotated: "2026-04-08", rotationPolicyDays: 90 });
    const result = classifySecret(secret, { now: NOW, warningWindowDays: 14 });

    expect(result.status).toBe("warning");
    expect(result.daysUntilDue).toBe(10);
  });

  it("marks a secret EXPIRED when past its rotation policy", () => {
    // Rotated 200 days ago with a 90-day policy -> overdue.
    const secret = makeSecret({ lastRotated: "2025-12-09", rotationPolicyDays: 90 });
    const result = classifySecret(secret, { now: NOW, warningWindowDays: 14 });

    expect(result.status).toBe("expired");
    expect(result.expired).toBe(true);
    expect(result.daysUntilDue).toBeLessThan(0);
  });

  it("treats a secret due exactly today as warning even with a 0-day window (boundary)", () => {
    // 2026-03-29 + 90 days = 2026-06-27 = NOW, so daysUntilDue is exactly 0.
    const secret = makeSecret({ lastRotated: "2026-03-29", rotationPolicyDays: 90 });
    const result = classifySecret(secret, { now: NOW, warningWindowDays: 0 });
    // daysUntilDue == 0 satisfies 0 <= 0, so it is a warning, not expired and not ok.
    expect(result.daysUntilDue).toBe(0);
    expect(result.status).toBe("warning");
    expect(result.expired).toBe(false);
  });
});
