/**
 * Cycle 2 (red/green TDD): config parsing/validation + full report building.
 *
 * Validation is where most real-world breakage lives (typos, wrong types,
 * impossible dates), so every failure path asserts a *specific, meaningful*
 * error message — requirement 5 ("handle errors gracefully").
 */
import { describe, expect, test } from "bun:test";
import { parseConfig, validateSecretConfig } from "../src/config";
import { buildReport, parseDate } from "../src/validator";
import type { SecretConfig } from "../src/types";

const NOW = parseDate("2026-06-28");

describe("parseConfig", () => {
  test("accepts an object with a secrets array", () => {
    const cfg = parseConfig({
      secrets: [
        { name: "A", lastRotated: "2026-01-01", rotationPolicyDays: 90, requiredBy: ["api"] },
      ],
    });
    expect(cfg).toHaveLength(1);
    expect(cfg[0]!.name).toBe("A");
  });

  test("accepts a bare top-level array of secrets", () => {
    const cfg = parseConfig([
      { name: "A", lastRotated: "2026-01-01", rotationPolicyDays: 90, requiredBy: [] },
    ]);
    expect(cfg).toHaveLength(1);
  });

  test("defaults a missing requiredBy to an empty array", () => {
    const cfg = parseConfig([{ name: "A", lastRotated: "2026-01-01", rotationPolicyDays: 90 }]);
    expect(cfg[0]!.requiredBy).toEqual([]);
  });

  test("rejects a config that is neither an array nor a {secrets} object", () => {
    expect(() => parseConfig(42)).toThrow(/array of secrets or an object/);
    expect(() => parseConfig({ nope: true })).toThrow(/array of secrets or an object/);
  });

  test("rejects a non-array secrets field", () => {
    expect(() => parseConfig({ secrets: "oops" })).toThrow(/"secrets" must be an array/);
  });
});

describe("validateSecretConfig error messages", () => {
  test("requires a non-empty name", () => {
    expect(() => validateSecretConfig({ lastRotated: "2026-01-01", rotationPolicyDays: 1 }, 0)).toThrow(
      /"name" is required/,
    );
    expect(() => validateSecretConfig({ name: "  ", lastRotated: "2026-01-01", rotationPolicyDays: 1 }, 0)).toThrow(
      /"name" is required/,
    );
  });

  test("requires a valid lastRotated date and surfaces the secret name", () => {
    expect(() =>
      validateSecretConfig({ name: "DB", lastRotated: "yesterday", rotationPolicyDays: 1 }, 3),
    ).toThrow(/secret "DB".*Invalid date "yesterday"/);
  });

  test("requires a positive integer rotationPolicyDays", () => {
    expect(() =>
      validateSecretConfig({ name: "DB", lastRotated: "2026-01-01", rotationPolicyDays: 0 }, 0),
    ).toThrow(/"rotationPolicyDays" must be a positive integer/);
    expect(() =>
      validateSecretConfig({ name: "DB", lastRotated: "2026-01-01", rotationPolicyDays: -5 }, 0),
    ).toThrow(/"rotationPolicyDays" must be a positive integer/);
    expect(() =>
      validateSecretConfig({ name: "DB", lastRotated: "2026-01-01", rotationPolicyDays: 1.5 }, 0),
    ).toThrow(/"rotationPolicyDays" must be a positive integer/);
  });

  test("requires requiredBy (when present) to be an array of strings", () => {
    expect(() =>
      validateSecretConfig(
        { name: "DB", lastRotated: "2026-01-01", rotationPolicyDays: 1, requiredBy: "api" },
        0,
      ),
    ).toThrow(/"requiredBy" must be an array of service-name strings/);
    expect(() =>
      validateSecretConfig(
        { name: "DB", lastRotated: "2026-01-01", rotationPolicyDays: 1, requiredBy: [1, 2] },
        0,
      ),
    ).toThrow(/"requiredBy" must be an array of service-name strings/);
  });

  test("uses a 1-based positional label when the name is missing", () => {
    expect(() => validateSecretConfig({}, 4)).toThrow(/secret #5/);
  });
});

describe("buildReport", () => {
  const secrets: SecretConfig[] = [
    { name: "AWS_ACCESS_KEY", lastRotated: "2026-01-01", rotationPolicyDays: 90, requiredBy: ["api", "worker"] },
    { name: "DB_PASSWORD", lastRotated: "2026-05-01", rotationPolicyDays: 60, requiredBy: ["api"] },
    { name: "STRIPE_API_KEY", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["billing"] },
    { name: "JWT_SIGNING_KEY", lastRotated: "2026-06-20", rotationPolicyDays: 30, requiredBy: ["auth"] },
  ];

  test("summary counts each urgency bucket and records the reference date + window", () => {
    const report = buildReport(secrets, NOW, 14);
    expect(report.generatedAt).toBe("2026-06-28");
    expect(report.warningWindowDays).toBe(14);
    expect(report.summary).toEqual({ total: 4, expired: 1, warning: 1, ok: 2 });
  });

  test("groups secrets by urgency", () => {
    const report = buildReport(secrets, NOW, 14);
    expect(report.groups.expired.map((s) => s.name)).toEqual(["AWS_ACCESS_KEY"]);
    expect(report.groups.warning.map((s) => s.name)).toEqual(["DB_PASSWORD"]);
    expect(report.groups.ok.map((s) => s.name)).toEqual(["JWT_SIGNING_KEY", "STRIPE_API_KEY"]);
  });

  test("sorts each group by soonest-to-expire first", () => {
    const manyExpired: SecretConfig[] = [
      { name: "LATER", lastRotated: "2026-04-01", rotationPolicyDays: 30, requiredBy: [] }, // expiry 2026-05-01
      { name: "EARLIER", lastRotated: "2026-01-01", rotationPolicyDays: 30, requiredBy: [] }, // expiry 2026-01-31
    ];
    const report = buildReport(manyExpired, NOW, 14);
    // Most overdue (smallest daysUntilExpiry) must come first.
    expect(report.groups.expired.map((s) => s.name)).toEqual(["EARLIER", "LATER"]);
  });

  test("handles an empty secret list", () => {
    const report = buildReport([], NOW, 14);
    expect(report.summary).toEqual({ total: 0, expired: 0, warning: 0, ok: 0 });
  });
});
