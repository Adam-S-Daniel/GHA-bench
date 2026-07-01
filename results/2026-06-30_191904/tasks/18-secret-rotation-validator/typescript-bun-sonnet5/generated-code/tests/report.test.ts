// Red/green TDD step 4: build the full rotation report, grouping every
// secret into expired/warning/ok notification buckets.
import { describe, expect, test } from "bun:test";
import { generateReport } from "../src/report.ts";
import type { SecretsConfig } from "../src/types.ts";

const NOW: Date = new Date("2026-07-01T00:00:00.000Z");

describe("generateReport", () => {
  const config: SecretsConfig = {
    warningWindowDays: 14,
    secrets: [
      // ok: 30 days since rotation, 90 day policy -> 60 days runway
      { name: "tls-cert", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["web"] },
      // warning: 80 days since rotation, 90 day policy -> 10 days runway
      { name: "api-key", lastRotated: "2026-04-12", rotationPolicyDays: 90, requiredBy: ["api"] },
      // expired: 100 days since rotation, 90 day policy -> 10 days overdue
      { name: "db-password", lastRotated: "2026-03-23", rotationPolicyDays: 90, requiredBy: ["db", "backup"] },
    ],
  };

  test("groups secrets into expired, warning, and ok buckets", () => {
    const report = generateReport(config, NOW);
    expect(report.expired.map((s) => s.name)).toEqual(["db-password"]);
    expect(report.warning.map((s) => s.name)).toEqual(["api-key"]);
    expect(report.ok.map((s) => s.name)).toEqual(["tls-cert"]);
  });

  test("includes total count and the effective warning window", () => {
    const report = generateReport(config, NOW);
    expect(report.totalSecrets).toBe(3);
    expect(report.warningWindowDays).toBe(14);
  });

  test("stamps generatedAt with the provided `now`", () => {
    const report = generateReport(config, NOW);
    expect(report.generatedAt).toBe(NOW.toISOString());
  });

  test("handles an empty secrets list", () => {
    const report = generateReport({ warningWindowDays: 14, secrets: [] }, NOW);
    expect(report.totalSecrets).toBe(0);
    expect(report.expired).toEqual([]);
    expect(report.warning).toEqual([]);
    expect(report.ok).toEqual([]);
  });

  test("an explicit CLI warning window overrides the config value", () => {
    // api-key has 10 days of runway; a 5-day window pushes it from warning to ok
    const report = generateReport(config, NOW, 5);
    expect(report.warningWindowDays).toBe(5);
    expect(report.warning.map((s) => s.name)).toEqual([]);
    expect(report.ok.map((s) => s.name)).toEqual(["tls-cert", "api-key"]);
  });
});
