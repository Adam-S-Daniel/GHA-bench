/**
 * TDD Cycle 3: report generation.
 *
 * generateReport evaluates every secret and groups the statuses into
 * expired / warning / ok buckets, most urgent first within each bucket
 * (ties broken by name so output is fully deterministic).
 */
import { describe, expect, test } from "bun:test";
import { generateReport } from "../src/report";
import type { SecretConfig } from "../src/types";

// Mixed fixture: with referenceDate 2026-07-02 and window 14 this yields
// 2 expired, 1 warning, 1 ok (see per-case comments).
const SECRETS: SecretConfig[] = [
  {
    name: "jwt-signing-key", // expires 2026-12-17 (+168d) -> ok
    lastRotated: "2026-06-20",
    rotationPolicyDays: 180,
    requiredBy: ["auth-service", "web-frontend", "billing-api"],
  },
  {
    name: "oauth-client-secret", // expires 2026-07-02 (0d) -> expired
    lastRotated: "2026-04-10",
    rotationPolicyDays: 83,
    requiredBy: ["web-frontend"],
  },
  {
    name: "db-password", // expires 2026-04-01 (-92d) -> expired
    lastRotated: "2026-01-01",
    rotationPolicyDays: 90,
    requiredBy: ["auth-service", "billing-api"],
  },
  {
    name: "api-key-stripe", // expires 2026-07-10 (+8d) -> warning
    lastRotated: "2026-05-01",
    rotationPolicyDays: 70,
    requiredBy: ["billing-api"],
  },
];

describe("generateReport", () => {
  const report = generateReport(SECRETS, {
    referenceDate: "2026-07-02",
    warningWindowDays: 14,
  });

  test("carries the evaluation parameters", () => {
    expect(report.referenceDate).toBe("2026-07-02");
    expect(report.warningWindowDays).toBe(14);
  });

  test("counts each urgency bucket", () => {
    expect(report.summary).toEqual({ expired: 2, warning: 1, ok: 1 });
  });

  test("groups secrets by urgency, most urgent first", () => {
    expect(report.groups.expired.map((s) => s.secret.name)).toEqual([
      "db-password", // -92 days
      "oauth-client-secret", // 0 days
    ]);
    expect(report.groups.warning.map((s) => s.secret.name)).toEqual([
      "api-key-stripe",
    ]);
    expect(report.groups.ok.map((s) => s.secret.name)).toEqual([
      "jwt-signing-key",
    ]);
  });

  test("breaks daysUntilExpiry ties by name", () => {
    const twin = (name: string): SecretConfig => ({
      name,
      lastRotated: "2026-01-01",
      rotationPolicyDays: 30,
      requiredBy: [],
    });
    const r = generateReport([twin("zeta"), twin("alpha")], {
      referenceDate: "2026-07-02",
      warningWindowDays: 14,
    });
    expect(r.groups.expired.map((s) => s.secret.name)).toEqual(["alpha", "zeta"]);
  });

  test("produces empty buckets for an empty config", () => {
    const r = generateReport([], {
      referenceDate: "2026-07-02",
      warningWindowDays: 14,
    });
    expect(r.summary).toEqual({ expired: 0, warning: 0, ok: 0 });
    expect(r.groups).toEqual({ expired: [], warning: [], ok: [] });
  });

  test("rejects a non-positive warning window with a clear error", () => {
    expect(() =>
      generateReport(SECRETS, { referenceDate: "2026-07-02", warningWindowDays: 0 }),
    ).toThrow(/warning window must be a positive integer/);
  });
});
