import { describe, expect, test } from "bun:test";
import { classifySecret, validateSecrets } from "./validator.ts";
import type { RotationConfig, SecretMeta } from "./types.ts";

// Fixed reference date so tests are deterministic regardless of when they run.
const REFERENCE_DATE = new Date("2026-07-01T00:00:00.000Z");

describe("classifySecret", () => {
  test("marks a secret as expired when its policy window has fully elapsed", () => {
    const secret: SecretMeta = {
      name: "db-password",
      lastRotated: "2026-01-01",
      rotationPolicyDays: 90,
      requiredBy: ["api-service"],
    };

    const status = classifySecret(secret, REFERENCE_DATE, 14);

    expect(status.urgency).toBe("expired");
    expect(status.daysUntilExpiry).toBeLessThanOrEqual(0);
  });

  test("marks a secret as warning when expiry falls within the warning window", () => {
    // Rotated 80 days ago, 90-day policy -> 10 days left, 14-day warning window.
    const secret: SecretMeta = {
      name: "api-key",
      lastRotated: "2026-04-12",
      rotationPolicyDays: 90,
      requiredBy: ["billing-service"],
    };

    const status = classifySecret(secret, REFERENCE_DATE, 14);

    expect(status.urgency).toBe("warning");
    expect(status.daysUntilExpiry).toBe(10);
  });

  test("marks a secret as ok when well within its rotation policy", () => {
    // Rotated 10 days ago, 90-day policy -> 80 days left, well beyond the warning window.
    const secret: SecretMeta = {
      name: "tls-cert",
      lastRotated: "2026-06-21",
      rotationPolicyDays: 90,
      requiredBy: ["edge-proxy"],
    };

    const status = classifySecret(secret, REFERENCE_DATE, 14);

    expect(status.urgency).toBe("ok");
    expect(status.daysUntilExpiry).toBe(80);
  });

  test("treats a secret expiring exactly at the warning boundary as warning", () => {
    // Rotated 76 days ago, 90-day policy -> 14 days left, exactly at the 14-day window edge.
    const secret: SecretMeta = {
      name: "oauth-secret",
      lastRotated: "2026-04-16",
      rotationPolicyDays: 90,
      requiredBy: ["auth-service"],
    };

    const status = classifySecret(secret, REFERENCE_DATE, 14);

    expect(status.urgency).toBe("warning");
    expect(status.daysUntilExpiry).toBe(14);
  });

  test("throws a clear error for an unparseable lastRotated date", () => {
    const secret: SecretMeta = {
      name: "broken-secret",
      lastRotated: "not-a-date",
      rotationPolicyDays: 30,
      requiredBy: [],
    };

    expect(() => classifySecret(secret, REFERENCE_DATE, 14)).toThrow(/Invalid date/);
  });
});

describe("validateSecrets", () => {
  test("groups classified secrets into expired/warning/ok buckets", () => {
    const config: RotationConfig = {
      warningWindowDays: 14,
      secrets: [
        { name: "db-password", lastRotated: "2026-01-01", rotationPolicyDays: 90, requiredBy: ["api-service"] },
        { name: "api-key", lastRotated: "2026-04-12", rotationPolicyDays: 90, requiredBy: ["billing-service"] },
        { name: "tls-cert", lastRotated: "2026-06-21", rotationPolicyDays: 90, requiredBy: ["edge-proxy"] },
      ],
    };

    const report = validateSecrets(config, REFERENCE_DATE);

    expect(report.expired.map((s) => s.name)).toEqual(["db-password"]);
    expect(report.warning.map((s) => s.name)).toEqual(["api-key"]);
    expect(report.ok.map((s) => s.name)).toEqual(["tls-cert"]);
    expect(report.warningWindowDays).toBe(14);
  });

  test("rejects a config with no secrets", () => {
    const config: RotationConfig = { warningWindowDays: 14, secrets: [] };

    expect(() => validateSecrets(config, REFERENCE_DATE)).toThrow(/at least one secret/);
  });

  test("rejects a negative warning window", () => {
    const config: RotationConfig = {
      warningWindowDays: -1,
      secrets: [{ name: "x", lastRotated: "2026-01-01", rotationPolicyDays: 30, requiredBy: [] }],
    };

    expect(() => validateSecrets(config, REFERENCE_DATE)).toThrow(/warningWindowDays/);
  });
});
